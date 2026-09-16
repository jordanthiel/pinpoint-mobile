# Round history and conflict handling

Verified 2026-09-15 with the iOS 26.3 Pinpoint Gesture QA simulator.

- Simulator build passed; smoke suite passed all 437 checks.
- Me → Rounds exposes the native trailing Delete action. Invoking its accessibility action displayed the deletion confirmation; dismissing it preserved the round. Automated mouse drags activated the row rather than revealing swipe actions, so the physical swipe gesture still needs device verification.
- Isolated store tests cover persisted round deletion, reload, and sync tombstone creation. No existing user rounds were deleted during QA.
- Round details show scoring, putting, penalties, shot counts, club distances, and recorded patterns.
- Hole-by-hole review showed both saved shots on hole 1. Tapping the first map marker opened its club, lie, and carry details. Final verification showed mapped distances of 173 and 153 yards, calculated from consecutive saved positions.
- Next hole displayed hole 2 with no final score and an explicit no-shots state. Review is read-only and independent of the active round.
- Merge regressions cover concurrent GPS/current-hole/weather changes without conflict copies, repeated GPS merges without duplicates, deterministic conflict-copy IDs, and retries with an already-preserved copy. Genuine score conflicts continue preserving both versions.
- Existing conflict copies remain available for review and manual deletion. No backend cleanup was performed.

Changes have not been uploaded to App Store Connect.
