# Round responsiveness fixes — 2026-09-15

## Changes

- A single shared phone CLLocationManager serves foreground screens and the active-round background tracker. Best accuracy replaces BestForNavigation; unused compass updates are removed. UI fixes are capped at 1 Hz, recent swing-resolution history at one minute. Stationary GPS remains enabled because dwell detection requires repeated fixes.
- Reject stale/inaccurate fixes and apply the five-second sampling limit before searching all 18 hole corridors.
- Score edits and GPS samples write a small atomic active-round journal alongside golf-state.json. They no longer encode all history, remote base and relational checkpoint on the interaction path. Canonical writes/checkpoints and journal writes share an ordered queue; canonical commits clear the journal. Startup overlays a newer journal matching the active-round ID. Read failure preserves files and reports unhealthy storage.
- Hidden tab content is unmounted, so Me/Improve analytics and inactive maps don't react to round GPS updates. Companion publishing no longer computes a full practice analysis during a round.
- The playing map uses flat satellite imagery instead of realistic 3D terrain. Processed GPS trails are cached across camera frames.
- Live Activity GPS updates use a five-second cadence with a trailing update, preserving the newest fix instead of dropping the last movement in a burst. Hole/score updates bypass that delay. Foreground reconciliation remains supported.
- Opening a round on Watch starts its golf workout session and swing tracking, with HealthKit authorization. An explicit stop is respected for that round. Ending a round stops tracking. The running tracker supplies distance GPS, avoiding a second Watch GPS receiver. Phone hole changes update the Watch tracker even while the Watch view is inactive. Main-queue motion callbacks no longer spawn 50 Tasks per second. Session startup is invalidated if the round ends during authorization.

## Validation

- iPhone and Watch simulator build passed.
- Regression suite: 422 checks, including GPS/score write ordering, edits during async cloud writes, journal reload, unchanged checkpoint bytes after scoring, and trail cache correctness.
- `PINPOINT_SMOKE_MAIN=tools/SyncPerformanceMain.swift bash tools/run-smoke.sh`: three fully populated 18-hole rounds, 120 GPS samples per hole, four shots per hole, remote base and checkpoint. Longest of 30 durable score saves: 16 ms on this Mac; 281,132-byte journal versus 2,588,243-byte canonical file (unchanged during those edits). Background reconciliation heartbeat gap 9 ms versus 555 ms in the deliberately main-thread baseline. These are host benchmarks, not phone frame-rate guarantees.
- Georgetown hole-2 cart movement replay in the QA simulator: observed rangefinder change from 356 to 320 to 284 yards. Existing round data retained. This does not exercise IMU sensors or prove hardware battery/thermal behavior.

## Remaining physical-device checks

Play several holes with phone locked between shots, Watch paired, signed in, and an existing round history. Check immediate hole changes in the Live Activity, distance updates roughly every five seconds while moving, Watch return-to-session after wrist lowering, score/shot edits while sync runs, battery use and thermal state. Record Instruments Time Profiler/Hangs/Energy traces if there is any delay.

watchOS controls return-to-clock behavior; an active workout supports background execution but cannot override the user's Return to Clock / Return to App settings. ActivityKit delivery is also system-controlled; five seconds is the app's update cadence, not a guaranteed display refresh deadline. See Apple's “Taking advantage of frontmost app state” and ActivityKit `update(_:)` documentation.
