# Pinpoint

Native SwiftUI golf app with four destinations:

- **Play:** course preview, active-round satellite GPS, target/club planning, scorecard, and voice catch-up.
- **Swings:** guided camera positioning, high-frame-rate capture, pose overlays, frame annotations, saved takeaway/top/impact markers, and tempo calculated from those markers.
- **Insights:** selectable round scope, scoring trends, putting/fairway/GIR evidence, club distances, shot patterns, and conversational coaching.
- **Improve:** practice priorities derived from recent recorded outcomes, drills, measurable targets, and a local practice journal.

## Voice and AI

Apple Intelligence and Apple's Speech recognizer are not used. The iPhone records a local mono AAC file, then submits it to the authenticated `golf-ai` Supabase Edge Function when the golfer stops. OpenAI `gpt-4o-transcribe` transcribes audio; `gpt-4.1-mini` handles structured recap extraction and coaching through the Responses API. Both models are configurable in server secrets.

Recordings are capped at ten minutes/8 MB. Upload errors retain audio on the phone for retry, including after closing/reopening the sheet. The user can explicitly discard a pending recording. Typed recaps remain usable without network access or sign-in.

Multi-hole narration accepts explicit hole numbers, ordinal references ("on the first", "second hole"), and "next hole". Scores, putts, penalties, fairways, clubs, lies, distances, contact, shape and notes can be reviewed before saving. Score-first putting totals are appended after full swings instead of being mistaken for the first shot. Saving replaces previous dictated shots on selected holes and preserves other shots. Remove overlapping entries when an existing shot trail already covers the recap. Failed writes retain the draft and restore the in-memory round.

OpenAI extraction uses a strict JSON schema, exact source quotes, and client-side field verification. Unsupported model details fall back to the deterministic parser. Unknown new dictated carry distances and first-putt distances remain unset. AI coaching gets computed aggregates and a bounded hole-evidence excerpt; it cannot see swing videos. Offline answers are explicitly labelled recorded-data summaries.

### Server setup

Provider keys must never be placed in the iOS plist, source code, or app bundle. For local development:

1. Copy `supabase/functions/.env.example` to `supabase/functions/.env` (git-ignored).
2. Set `OPENAI_API_KEY` in that file.
3. Run `supabase migration up --local`.
4. Run `supabase functions serve golf-ai --env-file supabase/functions/.env`.
5. Sign in to Pinpoint using the existing account flow. Use the **Sign in for OpenAI** shortcut in Voice recap or Insights.

For a deployed Supabase project, apply migrations, set the same provider secrets in the project, deploy `golf-ai`, and configure the app with that project's URL/client key. The handler verifies the session with Supabase Auth before any provider call. A Postgres quota allows 100 AI requests per user per UTC day; recap extraction uses one request for the entire transcript. The `round_recap` operation sends the complete transcript and current-hole/par context to the LLM, with strict JSON schema and temperature 0 for consistency (not a guarantee of identical generation). The LLM owns hole assignment, corrections, shot interpretation, score, putts, penalties and fairway results. Validation checks types, ranges, permitted values, unique/valid holes and transcript evidence quotes; it never requires agreement with the offline parser. Model fields populate editable review drafts directly. No score/putt totals synthesize extra shot events on save. Provider failures keep the transcript and show a retryable error; basic offline parsing is a separate explicit choice. The legacy `recap` operation remains compatible with older builds. Client-supplied model/key settings are ignored. Responses use `store: false`; normal provider data-handling policies still apply.

Reference: [OpenAI transcription](https://developers.openai.com/api/docs/guides/speech-to-text), [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs).

## Current coverage and storage

The bundled course is Georgetown Country Club. Individual-hole GPS and card yardages use its Blue-tee survey; the existing alternate-tee totals do not supply separate tee GPS surveys. Live GPS/imagery require their normal permissions/connectivity. There is no broader course-search backend in this repository.

Rounds (active, finished, and unfinished), scores, shots, pin/putt positions, penalties, structured observations, the club bag, and practice sessions sync to the signed-in Supabase account. Videos/tags retain the existing explicit swing upload flow. Swing-review drawing overlays and ephemeral coach chat are not part of golf-data sync.

Golf data is saved atomically in `golf-state.json` under an account-specific Application Support directory, with the last acknowledged cloud cursor, record mirror (including deletion markers), and merge base. Existing JSON files and the practice UserDefaults journal are migrated when the first account signs in; an ownership marker prevents importing those records into another account. Sign-out switches to a separate guest cache. Saved local changes are the durable offline queue.

Cloud data lives in typed `rounds`, `hole_scores`, `shots`, `clubs`, and `practice_sessions` tables. Composite ownership/parent foreign keys and owner-only RLS isolate accounts. `commit_golf_records` atomically compares each changed record’s revision; unrelated edits can both succeed. `pull_golf_records` downloads changes after a per-user cursor. That account row contains only sync metadata, not golf data. Deletes cascade tombstones to child records, preventing stale devices from resurrecting removed rounds. Known score/shot fields are ordinary columns; evolving observations and course geometry remain JSONB. Old `golf_sync_state` and `rounds_legacy_snapshot` payloads are retained as read-only migration sources; migration verifies entity counts and score totals before cutover. Old snapshot writes require an app upgrade. Sync runs after edits (debounced), sign-in, foregrounding, every 30 seconds while foregrounded, or Account → Sync golf data now. Offline errors leave local data intact and retry on those triggers. Devices must use the same account. The auth client emits its cached session before attempting refresh so offline restarts can open the correct cache.

Three-way merging combines independent edits by round, hole, shot, club, and practice-session identity. Deletions win over stale edits. Same-field conflicts keep the remote original and a labeled local conflict copy for review; raw data is never silently overwritten. Multiple independently started active rounds remain available in history and can be resumed. The account screen reports pending/synced/unavailable state.

Validation: `bash tools/run-smoke.sh` includes offline persistence, account isolation and merge checks. `PINPOINT_SYNC_FIXTURE=/tmp/pinpoint-sync-fixture.json bash tools/run-smoke.sh` generates real model fixtures. `python3 tools/test-golf-sync-local.py` checks actual local Auth/RLS, migration, independent/concurrent record revisions, delta reads, and cascading deletions; `--deployed` runs against the explicitly linked Pinpoint project using temporary QA accounts, which are deleted afterwards. Administrative credentials stay only in process memory and never enter the app bundle.

## Validation

Build with Xcode and the `Pinpoint` scheme, or:

```sh
xcodebuild -scheme Pinpoint -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

On an Apple Silicon Mac with macOS 26 and the Xcode 26 SDK:

```sh
tools/run-smoke.sh
```

The Swift smoke harness runs 91 checks against production parsing, evidence verification, models, analytics and round persistence. It substitutes only the unused hardware watch detector and disables network calls in the macOS harness. All store tests use temporary directories.

Backend checks:

```sh
deno check supabase/functions/golf-ai/index.ts
deno test supabase/functions/golf-ai/handler_test.ts
python3 tools/test-golf-ai-local.py
```

The 10 Deno tests use a mocked provider to verify authentication, quota rejection, multipart transcription, strict schemas, source evidence, incomplete responses and secret-safe errors. The local integration script checks real Supabase Auth, the Edge Function and Postgres quota using a temporary QA account, then deletes that account and its usage row. It makes no paid provider calls.

Simulator QA on iPhone 17 Pro / iOS 26.3 covered the Play layout, satellite map, score sheet, multi-hole review/save, journal save, restored original round data and OpenAI-unavailable fallback. It found and fixed invented AI shot details, score-summary putting order, and an incorrect first-render drill attempt count. The updated app builds for arm64 and x86_64 simulators.

Live OpenAI transcription/coaching remain unverified until the server API key is supplied. This Simulator could not start audio recording with its current host input route; physical-device audio/camera capture and real swing-video review still need testing.

## Apple Watch and golf-cart CarPlay

The project now has three shared schemes:

- **Pinpoint**: the standard iPhone app, embedding **PinpointWatch**.
- **PinpointWatch**: a native watchOS 10+ companion (`com.pinpointreplay.mobile.watchkitapp`).
- **Pinpoint Cart**: an alternative build of the same iPhone app with a CarPlay scene and the Watch app embedded. It intentionally uses the same iPhone bundle identifier and local round data. Install this variant instead of the standard build, not alongside it.

The Watch provides cached round/hole information, explicitly refreshed Watch GPS distance to the pin, quick score/putt editing, hole selection, skip/next, a practice focus, and two-minute voice notes. Score saves require the paired phone to be reachable; failed saves keep the current editor open. Edits include a round ID and a hole revision, so another round or a newer phone edit cannot be overwritten. Absolute score retries are idempotent. It does not run automatic swing detection or record video.

Watch voice notes transfer as AAC files with round/hole identifiers. Completed recordings stay in the Watch outbox until a durable-storage receipt comes back from iPhone. On iPhone, open **Play → Watch voice notes → Transcribe & Review**. This uses the existing authenticated OpenAI endpoint; review and save structured scores through the existing recap editor. No Apple Intelligence or Apple speech recognition is used. Notes for a different round are retained but cannot be applied to the current round. Provider/backend setup is still required as described above.

The cart interface provides current hole/par, GPS pin distance (or explicitly labeled tee/last-shot distance), large score and putt choices, Next/Skip, a hole scorecard, and a short practice focus. Scoring is shared with the iPhone immediately because the CarPlay scene runs in the same process and uses the same RoundStore. It uses two-level CarPlay list templates. Satellite shot planning, video recording/review, and full conversational analysis remain on iPhone. CarPlay microphone recording is not included in this category.

### CarPlay distribution prerequisite

`Config/CarPlay.entitlements` requests `com.apple.developer.carplay-driving-task` **only for the Pinpoint Cart target**. This is a development configuration, not evidence of approval. Apple must approve a suitable CarPlay entitlement and provisioning profile before distribution or use on a real cart screen. Golf-cart use does not itself establish eligibility under Apple's driving-task category; the request should explicitly describe golf scoring and on-course use. Do not describe it as road navigation or assume acceptance. The ordinary Pinpoint/Watch target has no CarPlay entitlement.

The Watch companion bundle identifier must be registered under the existing team, with automatic signing enabled. Keep host and Watch marketing/build versions aligned when archiving. The cart and standard host share the same companion identifier.

Apple references: [CarPlay developer page](https://developer.apple.com/carplay/), [CarPlay Developer Guide](https://developer.apple.com/download/files/CarPlay-Developer-Guide.pdf), [Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity).

### Validation — September 13, 2026

- Standard iPhone/embedded Watch and cart schemes built for iOS Simulator (arm64/x86_64); Watch built for watchOS Simulator. Simulator-signed cart and Watch builds also passed.
- Paired iOS 26.5 and watchOS 26.5 simulators exchanged the actual front-nine round. Cached Watch round ID, hole count and course matched the iPhone's persisted round. Watch rendered the synced course and score button.
- The signed cart variant registered and appeared in the CarPlay simulator launcher. The automation surface did not reliably route taps to the secondary CarPlay/Watch display, so a complete interactive cart/Watch scoring pass is still required on supported hardware or manually in Simulator.
- `bash tools/run-smoke.sh`: 121 checks passed, including companion wire decoding, score saving, duplicate retries, stale-edit rejection, and wrong-round rejection.
- Real microphone recordings, background audio transfers, wrist GPS accuracy, and the real cart display remain hardware checks. The existing OpenAI deployment/key limitation still applies.

Build examples:

```sh
xcodebuild -scheme Pinpoint -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme PinpointWatch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme 'Pinpoint Cart' -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

For CarPlay launcher testing, use normal Xcode simulator signing: an unsigned build compiles but does not carry the simulated CarPlay entitlement. In Simulator use I/O → External Displays → CarPlay. Do not manually re-sign the simulator binary; Xcode also embeds simulated entitlements in the executable.

## Structured voice observations

Reviewed voice shots retain typed finish location, lateral and depth misses (independent axes), putt break, high/low putt misses, explicit holed result, and starting distance alongside existing contact and shape. Travel distance, explicit carry, and remaining distance are stored separately. Only explicit carry enters carry analytics. Unknown observations remain nil; older saved shots decode without migration. A miss direction does not imply a shape, heel contact is distinct from shank, and pin-high descriptions do not manufacture distances. Individually narrated putts retain separate observations.

The recap editor exposes these fields for correction before saving. Coach evidence includes per-club observation counts and per-shot fields. OpenAI extraction requests the expanded schema; client grounding checks quoted evidence against the local parser and falls back conservatively when unsupported. Unrecognized wording remains in the original transcript for review. Live transcription/extraction requires the server provider key; smoke tests use deterministic parsing and mocked provider responses.

## Watch swing tracking and score entry

Start **Track swings** on the Watch's Shots page to run a golf activity session. Core Motion samples at 50 Hz. A two-second quiet wrist setup, acceleration/rotation burst, and (when accurate GPS is available) at least eight seconds stopped within a 12-meter area create a *candidate*. A ten-second cooldown reduces follow-through duplicates. Stop tracking from the same page. HealthKit workout processing keeps the golf session active with the wrist lowered; motion and location permissions are required. This is a heuristic, not a trained strike classifier: real-world sensitivity, practice-swing rejection, and battery use need on-course hardware validation. No microphone or Apple Intelligence is used for this detector.

Candidates persist on Watch and use queued WatchConnectivity user-info transfers. Phone receipts are returned only after durable storage. Repeated deliveries cannot add another shot, including after confirmation/dismissal. Position preference is accurate Watch GPS, a phone fix within 20 seconds of the event, then the last recorded shot position or hole tee, labeled **Estimated**. Phone backup GPS runs during an active round, including supported background location updates; older/offline events without a matching fix use the estimate. No fabricated carry or true-distance measurement is derived from these positions.

Orange markers on the phone hole map open review: move the map under the crosshair, choose a club/hole, confirm, or dismiss a practice swing. The Watch Tracking inbox provides the same review for all holes. Confirmed Watch shots use their swing-origin position on the map, and their editor supports moving that position. Pending events never affect scores. An existing recorded total is preserved when shots are confirmed.

New score sheets start unselected, with Save disabled. Penalties are included in the entered total; putts plus penalties cannot exceed it. Phone and Watch support penalty entry. Scorecard, round summary, bottom hole control, and Watch score displays use circles under par, a square for bogey, and double squares for double bogey or worse (double circles for eagle or better).

## Post-score shot mapping

On the live hole, **Save & Set Pin** now opens a single full-screen sequence: confirm pin → confirm first-putt position → shot overview. Zero recorded putts bypass first-putt placement. Skip leaves that step's existing data untouched. Pin/putt changes save only on confirmation, including the first-putt coordinate; moving a confirmed pin recalculates its distance. The round advances only from the overview's Next Hole action. The final hole opens the scorecard. Editing the score from the overview returns to the overview.

The overview uses native MapKit annotations for numbered swing origins, a putt callout, distance lines, and pending Watch candidates. Tapping a shot opens its editor and location correction; no detail editor is opened automatically. Missing positions may be shown as labeled placement suggestions derived from the score minus known putts and penalties, following the hole corridor. Suggestions remain UI-only until reviewed and saved; they do not become measured carries or recorded strokes just by viewing or leaving the overview.

Validation: simulator checks exercised score→pin→putt→overview, visible markers, tapping a shot to open details, returning to overview, and Next Hole navigation. The simulator's original active round was restored afterward. Regression checks cover coordinate persistence and recalculating first-putt distance after a pin edit.
