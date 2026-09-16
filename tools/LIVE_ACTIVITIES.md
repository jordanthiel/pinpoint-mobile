# Round Live Activities

An active round automatically starts one Live Activity when Pinpoint is in the foreground.
It shows hole, par, pin yardage, and the entered score. Lock Screen also shows course and
completed-hole total. Tap on iPhone to open that round. Saving, discarding, finishing, or
switching away from the round ends its activity.

The WidgetKit extension is embedded in both phone targets. On iOS 18+, it declares the
small supplemental activity family, providing the custom CarPlay (iOS 26+) / Watch
presentation. This does not depend on the separate Cart app's CarPlay entitlement.
CarPlay decides where/when to present the activity and disables interactive controls.

GPS reuses the existing round location session. Updates are coalesced to at most one
per ten seconds; score/hole changes publish immediately. Unchanged snapshots refresh
at most every 30 seconds. No database/network work happens in the extension.
Off-course, old, or inaccurate GPS falls back to the existing ball/tee estimate and is
labeled Estimated. Content expires after 60 seconds without an update, replacing the
old yardage with a refresh message. No remote ActivityKit push service is required.

## Verification

- Run `bash tools/run-smoke.sh` for snapshot/score/GPS regression checks.
- Build the Pinpoint scheme (includes Watch and Live Activity extension).
- Start/resume a round, then leave Pinpoint to see Dynamic Island or lock iPhone.
- Walk the Georgetown GPS route: yardage changes should be no more frequent than 10s.
- Change holes or save a score: the corresponding values should update promptly.
- Tap the activity: it must open the matching active round, not a historic round.
- Save unfinished / finish / discard: the activity must disappear.
- Sign out: the prior account's round must disappear.
- On an iOS 26+ phone connected to CarPlay, check the Dashboard small presentation.
  Physical CarPlay presentation still requires a connected compatible display.
- Disable Live Activities in iOS Settings: round tracking must continue normally.

Apple reference: https://developer.apple.com/documentation/ActivityKit/creating-custom-views-for-live-activities
