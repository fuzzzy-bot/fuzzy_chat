use std::cell::Cell;
use std::path::Path;
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::Arc;

use flutter_rust_bridge::frb;
use zeroize::Zeroizing;

use crate::api::core::CryptoCore;
use crate::error::CoreError;
use crate::files::{self, FileSetup, Progress, JOB_CANCELLED, JOB_PAUSED, JOB_RUNNING};
use crate::frb_generated::StreamSink;

/// One event of a file job — maps 1:1 onto the app's `FileProcessingProgress`.
///
/// `progress` is the fraction of chunks done (one event per chunk). The last
/// event is terminal: `is_complete` on success, `is_cancelled` after
/// [`FileJob::cancel`], or `is_complete` with an `error_message` (the
/// [`CoreError`]'s text: `wrong password`, `corrupt`, `unsupported format`,
/// `io`, `store locked`, `internal`) on failure — no `Err` ever reaches Dart,
/// because frb does not await a stream function's result (`unawaited`).
pub struct FileProgress {
    pub progress: f64,
    pub is_complete: bool,
    pub is_cancelled: bool,
    pub error_message: Option<String>,
}

impl FileProgress {
    fn running(progress: f64) -> Self {
        Self {
            progress,
            is_complete: false,
            is_cancelled: false,
            error_message: None,
        }
    }

    fn finished(progress: f64, result: Result<(), CoreError>) -> Self {
        match result {
            Ok(()) => Self {
                progress: 1.0,
                is_complete: true,
                is_cancelled: false,
                error_message: None,
            },
            Err(CoreError::Cancelled) => Self {
                progress,
                is_complete: false,
                is_cancelled: true,
                error_message: None,
            },
            Err(error) => Self {
                progress,
                is_complete: true,
                is_cancelled: false,
                error_message: Some(error.to_string()),
            },
        }
    }
}

/// The pause/resume/cancel handle of one file job. Create it with
/// [`new_file_job`], hand it to `encrypt_file`/`decrypt_file`, and call the
/// methods from Dart while the job runs; the loop reads the word before every
/// chunk. Holds no secret, so the methods are sync.
#[frb(opaque)]
pub struct FileJob {
    state: Arc<AtomicU8>,
}

pub fn new_file_job() -> FileJob {
    FileJob {
        state: Arc::new(AtomicU8::new(JOB_RUNNING)),
    }
}

impl FileJob {
    /// The loop finishes the chunk in flight, then sleeps 50 ms at a time until
    /// [`FileJob::resume`] or [`FileJob::cancel`].
    #[frb(sync)]
    pub fn pause(&self) {
        let _ = self.state.compare_exchange(
            JOB_RUNNING,
            JOB_PAUSED,
            Ordering::AcqRel,
            Ordering::Acquire,
        );
    }

    /// Continues a paused job at the next chunk boundary; a no-op otherwise.
    #[frb(sync)]
    pub fn resume(&self) {
        let _ = self.state.compare_exchange(
            JOB_PAUSED,
            JOB_RUNNING,
            Ordering::AcqRel,
            Ordering::Acquire,
        );
    }

    /// Terminal: the loop unlinks `<output>.part` and emits `is_cancelled` at
    /// the next chunk boundary (also while paused).
    #[frb(sync)]
    pub fn cancel(&self) {
        self.state.store(JOB_CANCELLED, Ordering::Release);
    }
}

/// Encrypts the file at `input` into the password-mode 0x04 container at
/// `output` (`.part` until the last chunk is written and fsynced), streaming
/// one [`FileProgress`] per 1 MiB chunk into `sink`. The file key is
/// Argon2id(password) with a fresh salt. Runs on frb's pool; the store must be
/// unlocked (`store locked` otherwise).
pub fn encrypt_file(
    core: &CryptoCore,
    password: String,
    input: String,
    output: String,
    job: &FileJob,
    sink: StreamSink<FileProgress>,
) {
    let password = Zeroizing::new(password.into_bytes());
    run(&sink, job, |job, progress| {
        core.opened()?;
        let setup = FileSetup::random()?;
        files::encrypt_with_password(
            &password,
            &setup,
            Path::new(&input),
            Path::new(&output),
            job,
            progress,
        )
    });
}

/// Decrypts the password-mode container at `input` to `output`, writing each
/// chunk to `<output>.part` only after its tag verified and renaming at the
/// end; on any failure or cancel the `.part` is removed and no output exists.
/// Failure text: `wrong password` (chunk 0 does not open), `corrupt` (a later
/// chunk, a truncation or appended bytes), `unsupported format` (not a
/// password-mode container).
pub fn decrypt_file(
    core: &CryptoCore,
    password: String,
    input: String,
    output: String,
    job: &FileJob,
    sink: StreamSink<FileProgress>,
) {
    let password = Zeroizing::new(password.into_bytes());
    run(&sink, job, |job, progress| {
        core.opened()?;
        files::decrypt_with_password(
            &password,
            Path::new(&input),
            Path::new(&output),
            job,
            progress,
        )
    });
}

/// Runs `work` with a progress callback that forwards to `sink`, then emits
/// the terminal event. Send failures are ignored: Dart dropping the stream
/// must not fail the job (the `.part` rules hold regardless).
fn run(
    sink: &StreamSink<FileProgress>,
    job: &FileJob,
    work: impl FnOnce(&AtomicU8, Progress<'_>) -> Result<(), CoreError>,
) {
    let last = Cell::new(0.0);
    let result = work(&job.state, &mut |progress| {
        last.set(progress);
        let _ = sink.add(FileProgress::running(progress));
    });
    let _ = sink.add(FileProgress::finished(last.get(), result));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn job_state_transitions() {
        let job = new_file_job();
        let state = |job: &FileJob| job.state.load(Ordering::Acquire);
        assert_eq!(state(&job), JOB_RUNNING);
        job.resume();
        assert_eq!(state(&job), JOB_RUNNING, "resume while running is a no-op");
        job.pause();
        assert_eq!(state(&job), JOB_PAUSED);
        job.pause();
        assert_eq!(state(&job), JOB_PAUSED);
        job.resume();
        assert_eq!(state(&job), JOB_RUNNING);
        job.pause();
        job.cancel();
        assert_eq!(state(&job), JOB_CANCELLED, "cancel wins over pause");
        job.resume();
        assert_eq!(state(&job), JOB_CANCELLED, "cancel is terminal");
        job.pause();
        assert_eq!(state(&job), JOB_CANCELLED);
    }

    #[test]
    fn terminal_events_follow_the_dart_contract() {
        let done = FileProgress::finished(0.4, Ok(()));
        assert!(done.is_complete && !done.is_cancelled && done.error_message.is_none());
        assert_eq!(done.progress, 1.0);

        let cancelled = FileProgress::finished(0.4, Err(CoreError::Cancelled));
        assert!(cancelled.is_cancelled && !cancelled.is_complete);
        assert_eq!(cancelled.progress, 0.4);
        assert!(cancelled.error_message.is_none());

        let failed = FileProgress::finished(0.4, Err(CoreError::WrongPassword));
        assert!(failed.is_complete && !failed.is_cancelled);
        assert_eq!(failed.error_message.as_deref(), Some("wrong password"));
        assert_eq!(
            FileProgress::finished(0.0, Err(CoreError::Corrupt))
                .error_message
                .as_deref(),
            Some("corrupt")
        );
        assert_eq!(
            FileProgress::finished(0.0, Err(CoreError::StoreLocked))
                .error_message
                .as_deref(),
            Some("store locked")
        );
    }
}
