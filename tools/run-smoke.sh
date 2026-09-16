#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_build_dir=$(mktemp -d /tmp/pinpoint-smoke.XXXXXX)
trap 'rm -rf "$task_build_dir"' EXIT
xcrun swiftc -D PINPOINT_STORE_SMOKE -target arm64-apple-macosx26.0 \
    LiveActivityShared/GolfActivityState.swift Pinpoint/Models/GolfActivitySnapshot.swift Pinpoint/Services/CourseWeather.swift Pinpoint/Models/CatalogCourse.swift Pinpoint/Models/FairwayResult.swift Pinpoint/Models/GeorgetownFairways.swift Pinpoint/Models/CourseWind.swift Pinpoint/Models/HandicapEstimate.swift Pinpoint/Models/ShotReview.swift Pinpoint/Models/LocationTrail.swift Pinpoint/Models/RoundModels.swift Pinpoint/Models/CourseGPS.swift \
    Pinpoint/Models/GolfSyncState.swift Pinpoint/Models/ClubBag.swift Pinpoint/Services/CaddieEngine.swift \
    Pinpoint/Services/HoleDictationParser.swift Pinpoint/Services/HoleRecapLLM.swift \
    Pinpoint/Services/RoundRecapParser.swift Pinpoint/Services/GolfInsights.swift Pinpoint/Services/RoundStore.swift Pinpoint/Services/OpenAIGolfService.swift \
    Shared/CompanionContract.swift Shared/SwingDetection.swift Pinpoint/Companion/CompanionScoreService.swift \
    "${PINPOINT_SMOKE_MAIN:-tools/DictationSmokeMain.swift}" -o "$task_build_dir/smoke"
"$task_build_dir/smoke"
