# TASK: Discoverable encrypted files and usable file-bubble actions

**Status:** IN_PROGRESS — implementation checkpoint only; independent QA and device coverage pending.

---
### PLAN (from HQ ticket)
- Address the owner's phone report: app-private file path and `null-` prefix in the bubble, inaccessible output, missing mobile Show, unreliable Share File and overflowing action pill. Keep the app offline.
- Source: `~/FuzzyCore_HQ/tickets/in_progress/T-0366-file-bubbles-rework-fuzzed-files-must-la.md`.

---
### IMPLEMENTATION (existing branch)
- Owning branch: `agent/T-0366-file-storage-rework`, original code commit `ff2b9590e94a8c8a8a174d45a1498f4098a5141d`, based on the combined colors/file-show line. It puts Android output in Downloads/Fuzzy Chat/<chat> via MediaStore and exposes iOS Documents in Files; file bubbles display name and human location; mobile Show returns; Share uses a content URI/MIME and the pill uses rows. This note changes no application code.
- Earlier Show and color work are ancestor commits (`T-0360`, `T-0361`), not independent proof that this rework is complete.

---
### REVIEW LOG (open gates)
- HQ ticket records 280 tests and analyze green at original implementation. Emulator API 35 at 360dp evidence is under `~/FuzzyCore_HQ/qa-reports/fuzzy_chat_T-0366_2026-09-22/` (screenshots for bubble, pill, Show, share sheet and a Downloads/activity log). No new tests or live checks were run for this documentation checkpoint.
- **Not verified:** real Samsung behavior, iOS, and received-file Open with a second party. Independent QA must re-verify before the ticket can move to resolved; emulator evidence alone is insufficient.

---
### DOCUMENTATION (handoff)
- Next worker: inspect HQ ticket/proofs, reproduce the original phone scenario and two-party received-file flow on target devices, then obtain separate QA/review. A pushed branch is parked, not merged or accepted.
