# Georgetown GPS test route

A repeatable, approximately 12-minute route through **Georgetown Country Club holes 1–3**, using the exact tees, hole corridors, green fronts and pins in `Pinpoint/Models/CourseGPS.swift`. The generator reads those coordinates directly so it can be regenerated when the app's mapping changes. Rough stops are synthetic offsets from the corridor; drive lines are QA routes, not surveyed cart paths.

The route pauses 25–45 seconds at each tee, fairway/rough landing area, chip and putt position. Cart legs run at 4–5 m/s (about 9–11 mph), slower transitions at 2–2.5 m/s, and walks near greens at 0.9–1.1 m/s. Hole 2 includes a rough recovery; hole 3 exercises a par-three tee shot. Stops refresh each second with 0.4-meter simulated GPS jitter. CoreSimulator may suppress identical-coordinate updates; this keeps dwell fixes fresh while remaining well inside the stop radius.

## Run in Simulator

1. Boot the iPhone simulator, open Pinpoint and allow location access. Start or select a **test** Georgetown round at hole 1. The script does not create rounds, change holes, enter scores, or inject shots.
2. Find the intended simulator UDID with `xcrun simctl list devices booted`.
3. From the project directory:

```sh
python3 tools/gps/play-route.py --device YOUR_IPHONE_SIMULATOR_UDID
```

For a paired, booted Watch, repeat `--device YOUR_WATCH_SIMULATOR_UDID` to play the same GPS route on both. Start Watch tracking separately. Choose hole 2 when its tee phase appears in the terminal (roughly 4:34), and hole 3 at roughly 9:21. Actual timing can be slightly longer due to simulator-command overhead.

Press **Ctrl+C** to stop; simulation is cleared on normal completion, interruption or failure. If forcibly killed, run `xcrun simctl location YOUR_UDID clear`. Disable any other Xcode/Simulator location scenario before playing so it does not compete with this route.

```sh
# Inspect the full timeline without touching a simulator:
python3 tools/gps/play-route.py --dry-run

# Short real-simulator test, starting with the first cart leg:
python3 tools/gps/play-route.py --device YOUR_UDID --from-phase 2 --limit-seconds 5

# Regenerate both data files after course mapping changes:
python3 tools/gps/build-georgetown-route.py
python3 tools/gps/play-route.py --export-gpx tools/gps/georgetown-country-club.gpx --dry-run
```

`georgetown-country-club.gpx` is also available to add to Xcode as a GPX location simulation file. It contains timestamped waypoint samples, including repeated coordinates during stops. **Use the Python player for stop-timing tests**: GPX playback behavior can vary by Xcode version. The player uses native `simctl location start` with explicit speeds for movement, and timed `set` updates for dwell periods.

## What this tests

- Continuous cart movement followed by sustained stationary locations.
- The Watch detector's 8-second dwell window, 12-meter anchor radius and fresh-fix requirement.
- Phone GPS backup positions, map tracking and transitions between mapped holes.

GPS alone does **not** generate accelerometer/gyroscope data. `WatchSwingTracker` also requires the motion gate in `Shared/SwingDetection.swift` to fire. Expect zero automatically confirmed swings from a GPS-only replay. This route exercises location behavior, not proof that a real wrist swing was detected. Use physical Watch swings or separately injected motion fixtures for the combined test; this player intentionally does not fabricate swing candidates.

Underlying mapped geometry: © OpenStreetMap contributors, [ODbL](https://www.openstreetmap.org/copyright), as embedded in GeorgetownGPS. No runtime network or API keys are needed.
