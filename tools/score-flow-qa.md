# Score flow regression notes — September 13, 2026

Tested on iPhone 17 Pro Simulator, iOS 26.3. Simulator build succeeded for arm64 and x86_64. `bash tools/run-smoke.sh` passed all 113 checks. No physical-device run or App Store Connect upload was performed for this patch.

## Reproduced and fixed

- Finish Hole saved a score but forced pin-location and first-putt dialogs before navigation. Skipping pin setup stranded the player on the original hole. Save & Next now advances directly after the score sheet dismisses; optional pin/putt tools return directly to the map.
- The bottom hole control never showed saved scores. It now shows the hole number and saved score, with an explicit edit accessibility label.
- Score actions were below the fold in a half-height sheet. The editor opens full height with pinned Save and Skip actions.
- No direct catch-up from a blank scorecard cell. Tapping a score now edits that hole and returns to the card without changing the current GPS hole.
- Existing high scores could be outside the displayed choices, and putts could exceed the score. Outlying scores remain visible, steppers support higher scores/putts, and invalid putt counts are prevented and rejected by the store.
- Skipped holes distorted the recap's to-par total. It now uses finished holes and labels that scope.
- Exit & Save Round left an empty navigation destination. Completing a round now returns to Play.

## Simulator checks

- Reopened hole 1: existing score 4 and two putts selected; saved 5/3 and advanced directly to hole 2.
- Changed hole 2's draft to 6, then skipped: advanced to hole 3; disk score and putts remained nil and isComplete remained false.
- Hole 3 defaulted to its own par (3), not the previous hole's selection.
- Selected score 1: putts clamped to 1 and larger putt buttons disabled.
- Closed the draft: remained on hole 3; reopening restored par 3/two putts rather than the cancelled draft.
- Disabled Track putts and saved: advanced to hole 4; scorecard displayed an unknown putt count, not zero.
- Edited skipped hole 2 through the scorecard: saved 13; total updated to 21; reopened with 13 preserved; current GPS hole stayed at 4.
- Saved hole 18: Save & View Scorecard presented the scorecard without a sheet race; total became 25.
- Relaunched: current hole 18, total 25, and four completed holes persisted.
- Loaded an isolated front-nine fixture at hole 9: final-hole label was correct; Skip opened the nine-hole scorecard and left hole 9 blank.
- Largest accessibility text size: Save and Skip remained visible, wrapped and tappable. Restored normal text size afterward.
- Finished the front-nine fixture: recap showed E for one completed par; Exit & Save returned to Play; finished round persisted in history.
- Restored the original simulator active round and history byte-for-byte after testing.

## Automated coverage added

Durable score edits and reloads; mapped-shot preservation; optional putts; invalid score/putt rejection without mutation; hole-in-one and high-score entry; skipping without scoring; current-hole persistence; front-nine, back-nine and eighteen-hole playing order including rotated starts; final-hole boundaries; failed disk writes reported with in-memory rollback.

## September 13 — fixed-center placement and shot corrections

- Pin and first-putt placement now use a one-time native camera setup and a fixed overlay marker. Removed tap-to-drop and annotation drag gestures that competed with map panning.
- Tap a shot → Move Shot Location opens a full-screen map with live mapped yardage, Use This Location, and Cancel. Save commits the draft; canceling the shot editor leaves the recorded shot unchanged. Map distance does not fabricate carry.
- Delete Shot is prominent for recorded and estimated positions. Persisted suppression prevents deleted positions from being recreated by the score-derived estimator. Entered scores remain unchanged.
- The overview has a separate flag. A putt marker only appears for a known first-putt location and positive putt count.
- iPhone + embedded Watch Debug build passed. All 181 smoke checks passed, including persisted movement, no fabricated carry, deletion/reload, replacement suppression, and unchanged score.
- Inspected the fixed flag placement in Simulator. End-to-end gesture QA was blocked by the computer-use server returning `noWindowsAvailable` for drag after reconnect/reset. Drag, confirm, cancel, and shot deletion should receive another simulator/device interaction pass before release.
- Original simulator active-round JSON restored byte-for-byte after the UI probe. No release upload for this change.

## September 13 — overview dragging, green zoom, and per-shot yardage

- Green camera distance reduced to 55 m; camera initialization deferred until MapKit has a nonzero viewport. Inspected close green framing with an 18-foot first-putt reference.
- Added direct overview marker pan handling, distinct tap-to-edit behavior, local distance/line previews, and atomic persisted shot position updates with rollback. Map pan/tap recognizers defer to marker gestures when a touch starts on a shot.
- Stroke endpoints use the next swing origin, then the first-putt position, then an explicitly saved landing. Cup fallback is allowed only for zero-putt finishes. Unknown approach yardages are omitted; putt lengths use feet, and estimated shot legs retain the approximation prefix.
- Estimated shot identities and vacant stroke numbers remain stable across edits. Editing a suggestion preserves its intended stroke number. Shot editor computes distance to pin from the current origin instead of displaying stale stored yardage.
- All 191 smoke checks pass, including a known geodesic distance, endpoint selection, persisted drag edits, invalid coordinates, and failed-write rollback. Final Debug phone/Watch build passed; diff whitespace check passed.
- Simulator connection restored by restarting Simulator. Automated drags still acted as taps (including on the plain placement map), so physical drag behavior remains unverified. Do not describe drag QA as passed. Original simulator round restored byte-for-byte after testing.

## September 13 — scoring and map interaction refinements

- Green placement starts at an 80 m camera distance. A dedicated one-finger pan copies the current camera and changes only its center; native scroll is disabled to avoid MapKit changing zoom when panning. Pinch zoom remains available. Flag artwork uses a thin pole and triangular pennant.
- Selecting a score suggests an editable putt count from score/par and any logged non-putting shots. Manual selections and existing known putts are preserved. No score remains selected on entry.
- Penalties button appears only after selecting score. Stroke rows are collapsed until tapped; opening them scrolls the rows into view. Assignments persist separately from the total so legacy unassigned penalties remain explicitly unassigned. Only physical strokes can receive penalties; score continues to include the total. The old shot-editor penalty controls were removed.
- Shot markers use blue teardrops, white centers, blue numbers, and compact black lie/club labels. Drag preview places a distance bubble above the finger, shifts nearby labels away, and changes the top bar to Distance to Pin.
- Actual Distance is populated from mapped endpoints and stored separately from carry and spoken travel. Moving a shot recalculates adjacent mapped distances and updates suggested clubs; manually selected clubs stay unchanged. Short chips never auto-convert into putts. AI evidence includes mapped distance, club suggestion provenance, and penalties by shot.
- Final iPhone/embedded Watch Debug build passed; all 207 regression checks passed. Simulator verified par -> 2 putts, penalty disclosure/assignment, Save -> pin placement, thin flag, blue shot icons, and populated Actual Distance. Simulator drag automation still produces taps rather than continuous movement, so physical pan/drag zoom and floating preview need device verification. Do not claim these gesture checks passed.
- Restored original simulator active round byte-for-byte. These changes have not been archived/uploaded.

## Placement jump correction

Removed the custom cumulative camera panning entirely. Placement uses native MapKit scrolling and a supported initial region span, with no camera writes during gestures. Initialization and other programmatic camera changes do not publish selected coordinates; only user-driven region changes do. Marker overlay and native map share the same frame (removed the map-only safe-area expansion). Added an explicit Reset to Green draft action. Debug phone/Watch build passed. Simulator verified initial first putt remains 18 ft and resetting recreates the map without changing that distance. Continuous physical dragging remains unverified; prior simulator drag injection behaves as a tap. Original simulator round restored. Not uploaded.

## September 14: shot-review persistence and GPS edge cases

- Review suggestions are committed together before Next Hole or Save & Return.
- Disk failures block leaving the review; repeated confirmation is idempotent.
- Missing tee GPS falls back to the mapped tee; a fairway stop can seed shot 2.
- Add shot is visible on the map and review, with a pinned Save Shot action.
- Saved counts and review access appear on the map and in the scorecard Shots row.
- Reviewing an existing score opens directly at shots; new scores start at the pin.
- GPS is assigned to the physical mapped hole while an earlier hole is being edited.
- Dotted movement overlays retain visibility independently of annotation collision.
- GPS gaps are left disconnected; missing movement samples are not fabricated.

Validation: 338 smoke checks passed. iPhone + Watch + Live Activity simulator build
passed. On iOS 26.5, confirmed two draft shots, advanced to hole 2, checked both shots
in on-disk storage, returned to hole 1 and verified both markers and the saved count.
Verified Add Shot opens for a scored hole and scorecard shows saved-shot controls.

## Background location and distance from last shot

- During an active round, the phone tracker requests When In Use first, then Always while foregrounded. The Always attempt is remembered; Tools → Background Location Settings allows later changes. No round means the background tracker stops.
- On a physical phone, test fresh permission, Allow Once, While Using, Always, denial, and returning from Settings. Lock the phone during the Georgetown route and verify new samples after unlocking. Force-quit is not a supported continuous tracking state.
- Phone map and Watch Distance page show distance from the saved shot origin, a newer pending IMU swing, or a departed GPS stop. Estimates are labeled; merely standing at the current stop must not reset the origin. No origin or stale current GPS shows a dash.
- Watch uses fresh Watch GPS first, then a fresh phone fix. Companion updates are throttled to ten seconds. Test Watch offline swing detection, reconnection, dismissed swing, hole change, and a saved/edited shot origin.
- Simulator build covers both iPhone and Watch. Physical background permission/locked-screen behavior and paired-device live updates still require device validation; simulator launch was blocked by CoreSimulator service failures in this session.

## Me tab and estimated handicap

- Me replaces Insights in the floating navigation. Insights (including an empty state) lead, followed by estimated handicap, stats/history, bag and account access. Existing coach and statistical breakdowns remain.
- Handicap detail shows counting rounds and links to their summaries. It uses saved, completed 18-hole rounds with known tee ratings, takes the newest 20 eligible rounds, and applies the published fewer-than-20 selection/adjustment table. Three rounds are required; plus handicaps display with a plus sign.
- Explicitly an estimate from gross scores, not an official Handicap Index: no maximum-hole adjustment, PCC, exceptional-score reduction or caps. Nine-hole and partial rounds remain in stats but are excluded from this estimate.
- New rounds persist the selected tee rating/slope snapshot in their existing round record; old Georgetown rounds can use the matching mapped tee. Unknown courses/tees never borrow Georgetown ratings.
- Verified Me tab and empty handicap drill-down on the QA simulator. Math, latest-20 window, exclusions, duplicate IDs and rating serialization are covered by smoke checks.

## Local wind

- NWS current station observations use mapped course coordinates, not player GPS; supports US courses. Georgetown resolves to KGTU (Georgetown Municipal Airport). No API key required. Weather source documentation: https://www.weather.gov/documentation/services-web-api
- Refresh when opening/resuming a round, then every ten minutes while foregrounded. Actor coalesces requests and caches successes ten minutes; failed requests back off for one minute. Response is saved only to the originating round/account.
- The wind card opens source/time details. Readings older than 90 minutes are stale; unavailable readings show a dash, never the legacy 5 mph default. Null direction is variable, not north. Null speed is missing, not calm.
- Direction is where wind comes FROM. The arrow points where it blows, relative to map heading; distance adjustment uses the bearing of each planning leg. No directional correction for variable wind.
- Live API + simulator verified KGTU 10 mph from SE, observed 4:10 PM on September 14. Smoke checks cover mph conversion, missing/invalid units, freshness, variable/calm wind and headwind/tailwind sign.

## Automatic fairway results

- Georgetown fairway polygons (including multipolygon inner rings) are bundled from OpenStreetMap, retrieved September 14, 2026. © OpenStreetMap contributors, ODbL 1.0: https://www.openstreetmap.org/copyright . Source bounding box: https://api.openstreetmap.org/api/0.6/map?bbox=-97.707,30.638,-97.690,30.655 . Polygons are associated with the hole whose mapped route intersects the largest part of the outer ring.
- Shot markers are origins: shot 2's position is the landing point of shot 1. An explicit first-shot endpoint also works. Own-green finishes count as successful fairway outcomes; par 3s are excluded.
- Explicit fairway overrides and reported shot outcomes/lies win over geometry. Default or inferred lies are not evidence of a hit. Assigned tee-shot penalties count as misses. Missing landing evidence remains unknown.
- Shot review displays the automatic result with a correction menu. Scorecard, round stats and Me/coach evidence share the same derived calculation. No cached Boolean is persisted, so moving/deleting a shot and cloud-synced location edits cannot leave stale inferred results.
- Verified shot review's Auto badge in the simulator. Smoke checks cover inside/outside polygons, polygon cutouts, marker movement/deletion, explicit endpoint, manual override/reset, explicit lie, tee penalties and par-3 exclusion.

## NFC club tags

- My Bag → Set up NFC club tags: assign, replace, unlink. Club entries carry optional nfcTagID and sync through existing relational bag records. Tags use stable MIFARE (NTAG213/215/216) or ISO15693 identifiers; tag contents are never written. NFC scan is foreground-only and initiated by the user.
- Round → Scan club → Scan club tag opens Apple's NFC reader. One callback logs one shot. Unknown/ambiguous tags, account/round changes, cancellation, unavailable hardware and write failures do not create shots. Same-tag scans within ten seconds on a hole are rejected.
- Location precedence: recent pending swing within 20 seconds (near fresh phone GPS when available), fresh on-hole phone GPS, estimated stop/tee. Estimates are labeled. Associated swing candidate is confirmed atomically to prevent a later duplicate review. Club bag identity and tag identity are kept on the shot; editing preserves them.
- Scores and measured carry are not overwritten. Saved scan offers edit/location adjustment or undo. The scan screen can open setup for unknown tags.
- Simulator navigation/unsupported hardware handling verified. 397 smoke checks pass, including NFC persistence, assignment conflict/reassignment, unknown tags, duplicate suppression, stale round, estimated tee fallback, and write rollback. Signed device build passes with the TAG entitlement. Actual radio scans, multi-tag detection and physical tag compatibility still require an NFC-capable iPhone.

## Score-implied shot counts — 2026-09-15

- Centralized `HoleScore.expectedShotCount`: recorded score minus recorded putts minus penalty strokes; unknown putts leave the count unknown.
- Score entry displays the physical-shot / putt / penalty breakdown. Map review fills missing slots from this count using existing stopped-location / tee fallbacks.
- Score/putt/penalty edits clear stale dismissed-suggestion counts. Deliberately deleted suggestions remain suppressed until that breakdown changes.
- A mismatch between mapped shots and the score is visible in review. Saved shots are never silently deleted to fit a new score.
- Regression cases: par-5 par with one putt (4 shots), par-3 birdie with one putt (1 shot), bogey, penalties, chip-in, ace, unknown putts, score edits after deletion, and preservation of excess saved shots.
- Simulator build passed; behavior covered by the smoke suite.

## Shot drag / live NFC logging — 2026-09-15

- Both SwiftUI playing-map and UIKit shot-review drags lift the placement coordinate by 56 screen points, so the marker stays above the finger. Snapping and distance calculations use that lifted coordinate; release saves the same visible location.
- `hasScore` now distinguishes a final score (or explicitly completed legacy card) from live shot counts. NFC/manual origins alone do not display a final score or imply hole completion.
- An origin-only last shot anchors the no-GPS rangefinder fallback at its start, instead of advancing by stock club distance. Known endpoints and measured carries keep their existing behavior.
- NFC sheet offers “Back to play” and explains that final score entry completes the hole.
- Regression coverage includes consecutive NFC scans, live shot numbering, current-origin fallback, no invented final green leg, and explicit score completion. NFC radio itself requires a physical iPhone.
