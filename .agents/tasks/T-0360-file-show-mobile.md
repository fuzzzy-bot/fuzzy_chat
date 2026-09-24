# TASK: Sent encrypted file — mobile Show action

**Status:** IN_REVIEW — implementation checkpoint only; not accepted or merged.

---
### PLAN (from HQ ticket)
- Replace the dead mobile `file://` directory launch with a usable file action for sent and received file bubbles; retain desktop reveal behavior.
- Source: `~/FuzzyCore_HQ/tickets/in_review/T-0360-sent-encrypted-file-show-does-nothing-on.md`.

---
### IMPLEMENTATION (existing branch)
- Owning branch: `agent/T-0360-file-show-mobile`, original code commit `2761859386037223d8184a41075ef7ac1ff7bdfb` (v1.1.0 line). `DeviceFileInteractor` uses a share sheet on mobile; mobile Show is hidden where it duplicates Share File; error toast and widget coverage were added. This note changes no application code.
- Later owner feedback found sharing still struggled and removing Show did not meet the need. The broader successor work is tracked by `T-0366` on `agent/T-0366-file-storage-rework`; do not treat this earlier branch as the final mobile UX.

---
### REVIEW LOG (open gates)
- HQ ticket records analyze and l10n/chat-UI/vault tests green **at the original implementation**, but live emulator QA was skipped. No new app tests or device QA were run for this documentation checkpoint.
- Independent mobile QA and acceptance of the actual file-access/share experience remain open; coordinate with the successor file-storage branch rather than claiming this branch resolves the owner's later report.

---
### DOCUMENTATION (handoff)
- Next worker: consult the HQ ticket and its successor `T-0366`; test on device and obtain independent QA before any merge/status change. This work record preserves the original branch context, not a completion certificate.
