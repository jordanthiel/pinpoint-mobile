# Course catalog

The iPhone Courses tab reads the public `course_catalog` view in the deployed Supabase project. It supports name/city/address search, a 50-mile nearby filter, course details, an Apple Maps directions handoff, and choosing a playable course. There is no in-app turn-by-turn navigation.

## Adding courses

Use the Supabase dashboard or trusted service-role tooling:

1. Add a `courses` row with a stable UUID, name, locality, address, latitude and longitude. Set `published` when ready to list it.
2. A directory-only course needs no hole data. Keep `playable` false; it offers directions but cannot start a round.
3. To enable play, add `course_tees` and all 18 `course_holes` definitions, including mapped tee/green/layout geometry. Hole JSON follows `CourseHole` in the app. Set `playable` true only after validating maps, tee yardages and ratings.
4. Refresh the Courses tab. Published additions appear without an app release.

The `course_catalog` view assembles a compatible GolfCourse definition from these tables. Anonymous and signed-in clients can only read published records; catalog editing is restricted to backend administration. Georgetown is currently the only seeded course, with four tees and all 18 mapped holes. Existing saved rounds are independent snapshots and are not rewritten by catalog changes.

The app caches the last successful response for offline browsing and preserves the selected course locally. Nearby filtering uses phone location locally; no user location is sent to the catalog endpoint. Distances in the directory are straight-line distances.

## Validation (2026-09-15)

- Migration deployed to wcobniubsmvvrggzrkhh.
- Anonymous REST catalog response verified: Georgetown, 18 holes, four tees.
- 401 smoke checks pass, including backend JSON decoding and mapped-hole preservation.
- iOS simulator build and manual directory/details/course-selection checks pass.
