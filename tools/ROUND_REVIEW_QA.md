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

## Build 29 — live round detail data

Round recap, scorecard, and shot review now resolve the selected round by ID from the observable store instead of retaining a value snapshot. Opening a saved recap requests fresh cloud data. The Rounds list includes tracked-shot count and SG; the recap places round SG next to the shot-review action. Saved scorecard shot counts now open read-only review.

Verified on iPhone 17 Pro simulator with the recovered cloud response: recap showed 39 tracked shots and -2.1 SG versus scratch (38 valued shots). Hole 1 review showed three mapped shots with clubs and distances. Opening the saved scorecard and tapping Hole 1's shot count reached the same three shots. Simulator storage was backed up and restored after the test. The DEBUG-only `--ui-round-review` probe reads a local Documents/round-review-fixture.json; no fixture data is included in the app.

Regression: `PINPOINT_RECORD_RESPONSE=<record-response.json> PINPOINT_SMOKE_MAIN=tools/RoundPresentationSmokeMain.swift tools/run-smoke.sh` verifies a selected round sees later cloud shots/SG and does not substitute another round if deleted. Full smoke suite and simulator build passed.
