import Foundation

#if PINPOINT_STORE_SMOKE
// Hardware detector is irrelevant to persistence and unavailable in this macOS harness.
final class WatchShotDetector {}
#endif

@main
struct DictationSmokeMain {
    @MainActor
    static func main() async {
        if let path = ProcessInfo.processInfo.environment["PINPOINT_EXPORT_COURSE"] {
            try! JSONEncoder().encode(SampleCourses.georgetown).write(to: URL(fileURLWithPath: path))
        }
        var failed = 0
        func check(_ name: String, _ cond: @autoclosure () -> Bool) {
            if cond() {
                print("ok   \(name)")
            } else {
                print("FAIL \(name)")
                failed += 1
            }
        }

        if let path = ProcessInfo.processInfo.environment["PINPOINT_CATALOG_RESPONSE"] {
            let catalog = try! JSONDecoder().decode([CatalogCourse].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            let remote = catalog.first { $0.id == SampleCourses.georgetown.id }
            check("Supabase catalog preserves existing course ID", remote != nil)
            check("Supabase tees and holes decode as playable course", remote?.definition?.holes.count == 18 && remote?.definition?.tees.count == 4)
            check("Supabase course retains mapped hole geometry", remote?.definition?.holes.first?.layout == SampleCourses.georgetown.holes.first?.layout)
            var directory = remote!; directory.definition = nil
            let decoded = try! JSONDecoder().decode(CatalogCourse.self, from: JSONEncoder().encode(directory))
            check("directory-only courses decode without shot maps", decoded.definition == nil)
        }

        var orderedBag = ClubBag(clubs: [
            ClubBagEntry(club: .putter, carryYards: 100),
            ClubBagEntry(club: .iron9, carryYards: 180),
            ClubBagEntry(club: .driver, carryYards: 160),
        ])
        orderedBag.add(.wood3)
        orderedBag.add(.iron7)
        orderedBag.remove(.iron9)
        orderedBag.add(.iron9, carryYards: 180)
        check("bag keeps standard order after adding and removing clubs", orderedBag.displayClubs.map(\.club) == [.driver, .wood3, .iron7, .iron9, .putter])
        let reorderedBag = ClubBag(clubs: orderedBag.clubs.reversed())
        check("bag order survives cloud record reordering", reorderedBag.displayClubs == orderedBag.displayClubs)
        check("recommendations still use personalized carry order", orderedBag.shotClubs.map(\.club) == [.iron7, .driver, .iron9, .wood3])

        let nfcFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nfcStore = RoundStore(storageDirectory: nfcFolder)
        nfcStore.startRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        let nfcClub = nfcStore.clubBag.displayClubs.first!
        let otherNFCClub = nfcStore.clubBag.displayClubs[1]
        let tag = "mifare:04010203040506"
        check("NFC tag assignment saves", nfcStore.assignNFCTag(tag, to: nfcClub.id))
        check("NFC tag cannot map to two clubs", !nfcStore.assignNFCTag(tag, to: otherNFCClub.id))
        let nfcID = nfcStore.activeRound!.id
        let nfcTee = nfcStore.activeRound!.teeCoordinate(for: 1)!
        check("unknown NFC tag does not log", nfcStore.logNFCShot(tag: "unknown", roundID: nfcID, hole: 1, phonePoint: nfcTee) == nil)
        let scanned = nfcStore.logNFCShot(tag: tag, roundID: nfcID, hole: 1, phonePoint: nfcTee)
        check("NFC scan logs mapped club and GPS", scanned?.club == nfcClub.club && scanned?.start == nfcTee && scanned?.bagEntryID == nfcClub.id)
        check("NFC scan does not fabricate score or measured carry", nfcStore.activeRound?.score(for: 1)?.recordedScore == nil && scanned?.includeInTrueDistance == false)
        check("NFC duplicate scan suppressed", nfcStore.logNFCShot(tag: tag, roundID: nfcID, hole: 1, phonePoint: nfcTee) == nil)
        check("NFC stale round rejected", nfcStore.logNFCShot(tag: tag, roundID: UUID(), hole: 1, phonePoint: nfcTee) == nil)
        let nfcHole = nfcStore.activeRound!.score(for: 1)!
        check("NFC scan is not a final score", !nfcHole.hasScore && !nfcHole.isComplete && nfcHole.recordedScore == nil)
        check("NFC fallback stays at scanned origin", nfcStore.activeRound!.ballCoordinate(for: 1) == nfcTee)
        check("NFC scan does not complete any holes", nfcStore.activeRound!.completedHoles.isEmpty)
        let nfcReload = RoundStore(storageDirectory: nfcFolder)
        check("NFC mappings and shots survive reload", nfcReload.clubBag.clubs.first(where: { $0.id == nfcClub.id })?.nfcTagID == tag && nfcReload.activeRound?.score(for: 1)?.shots.first?.nfcTagID == tag)
        let nfcFairway = nfcStore.activeRound!.playLayout(for: 1)!.point(afterTravelling: 150, toward: nfcStore.activeRound!.pinCoordinate(for: 1)!)
        let secondScan = nfcStore.logNFCShot(tag: tag, roundID: nfcID, hole: 1, phonePoint: nfcFairway, now: Date().addingTimeInterval(11))
        check("second NFC scan counts shots separately", secondScan?.number == 2 && nfcStore.activeRound!.score(for: 1)!.shots.count == 2 && !nfcStore.activeRound!.score(for: 1)!.hasScore)
        check("second NFC scan uses its current location", nfcStore.activeRound!.ballCoordinate(for: 1) == nfcFairway)
        check("NFC does not invent a final line to green", nfcStore.activeRound!.score(for: 1)!.recordedShotLegs(tee: nfcTee, pin: nfcStore.activeRound!.pinCoordinate(for: 1)!).count == 1)
        _ = nfcStore.saveScoreEntry(1, score: 4, putts: 2)
        check("final score completes NFC tracked hole", nfcStore.activeRound!.score(for: 1)!.hasScore && nfcStore.activeRound!.score(for: 1)!.isComplete && nfcStore.activeRound!.score(for: 1)!.recordedScore == 4)
        let fallbackScan = nfcStore.logNFCShot(tag: tag, roundID: nfcID, hole: 2, phonePoint: nil)
        check("NFC without GPS falls back to tee with estimate label", fallbackScan?.start == nfcStore.activeRound?.teeCoordinate(for: 2) && fallbackScan?.note.contains("estimated") == true)
        check("NFC unlink saves", nfcStore.assignNFCTag(nil, to: nfcClub.id))
        check("NFC unlinked tag stops matching", nfcStore.logNFCShot(tag: tag, roundID: nfcID, hole: 3, phonePoint: nfcTee) == nil)
        check("NFC tag can be reassigned after unlink", nfcStore.assignNFCTag(tag, to: otherNFCClub.id))
        let nfcFile = nfcFolder.appendingPathComponent("golf-state.json")
        try? FileManager.default.removeItem(at: nfcFile)
        try? FileManager.default.createDirectory(at: nfcFile, withIntermediateDirectories: true)
        let nfcBefore = nfcStore.activeRound
        check("NFC shot write failure reported", nfcStore.logNFCShot(tag: tag, roundID: nfcID, hole: 3, phonePoint: nil) == nil)
        check("NFC failed write rolls back", nfcStore.activeRound == nfcBefore)
        try? FileManager.default.removeItem(at: nfcFolder)

        var fairwayRound = GolfRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        let fairwayLayout = GeorgetownGPS.layout(for: 1)!
        let fairwayPoint = fairwayLayout.path[1]
        fairwayRound.holeScores[0].shots = [TrackedShot(number: 1, club: .driver, start: fairwayLayout.tee), TrackedShot(number: 2, club: .iron7, start: fairwayPoint)]
        check("selected second shot in mapped fairway is hit", fairwayRound.fairwayHit(for: 1) == true)
        fairwayRound.holeScores[0].shots[1].lie = .rough
        fairwayRound.holeScores[0].shots[1].lieWasInferred = false
        check("explicit shot lie overrides map inference", fairwayRound.fairwayHit(for: 1) == false)
        fairwayRound.holeScores[0].shots[1].lieWasInferred = true
        fairwayRound.holeScores[0].shots[1].start = fairwayPoint.offset(eastYards: 80, northYards: 0)
        check("moving second shot off fairway changes result", fairwayRound.fairwayHit(for: 1) == false)
        fairwayRound.holeScores[0].recordedFairwayHit = true
        check("manual fairway override survives map changes", fairwayRound.fairwayHit(for: 1) == true)
        fairwayRound.holeScores[0].recordedFairwayHit = nil
        check("clearing override restores automatic result", fairwayRound.fairwayHit(for: 1) == false)
        fairwayRound.holeScores[0].shots.removeLast()
        check("tee location alone does not imply fairway result", fairwayRound.fairwayHit(for: 1) == nil)
        fairwayRound.holeScores[0].shots[0].end = fairwayPoint
        check("explicit tee shot endpoint classifies without second shot", fairwayRound.fairwayHit(for: 1) == true)
        fairwayRound.holeScores[0].penaltiesByShot = [1: 1]
        check("tee-shot penalty is a miss", fairwayRound.fairwayHit(for: 1) == false)
        check("all Georgetown holes have fairway boundary data", GeorgetownFairways.holes.count == 18)
        let square = [GeoPoint(latitude: 0, longitude: 0), GeoPoint(latitude: 0, longitude: 4), GeoPoint(latitude: 4, longitude: 4), GeoPoint(latitude: 4, longitude: 0)]
        let cutout = [GeoPoint(latitude: 1, longitude: 1), GeoPoint(latitude: 1, longitude: 3), GeoPoint(latitude: 3, longitude: 3), GeoPoint(latitude: 3, longitude: 1)]
        let polygon = MappedFairway(outer: square, inner: [cutout])
        check("fairway polygon excludes bunker cutout", !polygon.contains(GeoPoint(latitude: 2, longitude: 2)))
        check("fairway polygon includes surrounding surface", polygon.contains(GeoPoint(latitude: 0.5, longitude: 0.5)))
        fairwayRound.holeScores[0].penaltiesByShot = nil
        fairwayRound.holesSnapshot[0].par = 3
        check("par three excluded from fairway stats", fairwayRound.fairwayHit(for: 1) == nil)

        let northWind = CourseWind(mph: 10, fromDegrees: 0, observedAt: Date(), station: "Test", stationID: "TEST")
        check("north wind is headwind when playing north", northWind.helping(toward: 0) == -1)
        check("north wind is tailwind when playing south", northWind.helping(toward: 180) == 1)
        check("wind kmh converts to mph", abs(CourseWind.milesPerHour(value: 16.09344, unit: "wmoUnit:km_h-1")! - 10) < 0.001)
        check("missing wind is not calm", CourseWind.milesPerHour(value: nil, unit: "wmoUnit:km_h-1") == nil)
        check("unknown wind unit rejected", CourseWind.milesPerHour(value: 10, unit: "unknown") == nil)
        check("old weather is stale", !northWind.isFresh(at: Date().addingTimeInterval(5401)))
        check("future weather rejected", !northWind.isFresh(at: Date().addingTimeInterval(-301)))
        var variableWind = northWind; variableWind.fromDegrees = nil
        check("variable wind has no invented headwind", variableWind.helping(toward: 0) == 0 && variableWind.compass == "Variable")
        variableWind.mph = 0
        check("zero-speed wind is calm", variableWind.compass == "Calm")
        if ProcessInfo.processInfo.environment["PINPOINT_LIVE_WEATHER"] == "1" {
            do {
                let wind = try await CourseWeather.shared.wind(at: GeorgetownGPS.courseCenter)
                check("live NWS observation decodes and is fresh", wind.isFresh() && wind.mph >= 0 && !wind.stationID.isEmpty)
                print("NWS: \(wind.stationID) \(wind.mph) mph from \(wind.compass)")
            } catch { check("live NWS request succeeds", false); print(error) }
        }

        check("handicap needs three eligible scores", HandicapEstimate.calculate([12, 14]) == nil)
        check("handicap initial three-score adjustment", HandicapEstimate.calculate([15.3, 15.2, 16.6]) == 13.2)
        check("handicap four-score adjustment", HandicapEstimate.calculate([12, 14, 16, 18]) == 11)
        check("handicap six-score adjustment", HandicapEstimate.calculate([10, 12, 14, 16, 18, 20]) == 10)
        check("handicap best eight of twenty", HandicapEstimate.calculate(Array(1...20).map(Double.init)) == 4.5)
        check("handicap oldest score drops out", HandicapEstimate.calculate(Array(repeating: 20.0, count: 20) + [-10]) == 20)
        check("handicap plus values stay negative internally", HandicapEstimate.calculate([-2, -1, 0]) == -4)
        check("handicap maximum is 54", HandicapEstimate.calculate([80, 80, 80]) == 54)
        var handicapRound = GolfRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        handicapRound.status = .finished
        for index in handicapRound.holeScores.indices {
            handicapRound.holeScores[index].recordedScore = 5
            handicapRound.holeScores[index].isComplete = true
        }
        check("handicap uses tee rating and slope", HandicapEstimate(rounds: [handicapRound]).entries.first?.differential == 21.3)
        check("handicap avoids duplicated round IDs", HandicapEstimate(rounds: [handicapRound, handicapRound]).entries.count == 1)
        let snapshotRound = try! JSONDecoder().decode(GolfRound.self, from: JSONEncoder().encode(handicapRound))
        check("handicap tee survives round serialization", snapshotRound.handicapTee?.rating == 67.6)
        handicapRound.savedHoleNumbers = Array(1...9)
        check("nine-hole round excluded from eighteen-hole estimate", HandicapEstimate(rounds: [handicapRound]).entries.isEmpty)
        handicapRound.savedHoleNumbers = nil
        handicapRound.status = .active
        check("active round excluded from handicap", HandicapEstimate(rounds: [handicapRound]).entries.isEmpty)
        handicapRound.status = .finished
        handicapRound.handicapTee = nil
        handicapRound.courseID = UUID()
        check("unknown historical course never borrows Georgetown rating", HandicapEstimate(rounds: [handicapRound]).entries.isEmpty)

        var distanceRound = GolfRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        let distanceTee = distanceRound.teeCoordinate(for: 1)!
        let distanceNow = Date()
        distanceRound.startedAt = distanceNow.addingTimeInterval(-120)
        check("last shot unavailable without evidence", distanceRound.lastShotAnchor(for: 1, current: distanceTee) == nil)
        distanceRound.holeScores[0].locationSamples = [0.0, 5, 10, 15].map {
            GolfLocationSample(point: distanceTee, timestamp: distanceNow.addingTimeInterval(-60 + $0), accuracy: 5, speed: 0)
        }
        check("current stop does not imply a played shot", distanceRound.lastShotAnchor(for: 1, current: distanceTee) == nil)
        let distanceAway = distanceTee.offset(eastYards: 100, northYards: 0)
        check("departed stop becomes estimated shot origin", distanceRound.lastShotAnchor(for: 1, current: distanceAway)?.estimated == true)
        check("other holes do not inherit last shot", distanceRound.lastShotAnchor(for: 2, current: distanceAway) == nil)
        distanceRound.holeScores[0].shots = [TrackedShot(number: 1, club: .driver, timestamp: distanceNow)]
        distanceRound.holeScores[0].shots[0].start = distanceTee
        check("saved shot supersedes older stop", distanceRound.lastShotAnchor(for: 1, current: distanceAway)?.estimated == false)
        distanceRound.swingCandidates = [SwingCandidate(roundID: distanceRound.id, hole: 1, timestamp: distanceNow.addingTimeInterval(1), latitude: distanceAway.latitude, longitude: distanceAway.longitude, accuracy: 5, locationSource: "watch", peakG: 3, rotation: 5, dwellSeconds: 10)]
        check("new IMU candidate supersedes saved origin", distanceRound.lastShotAnchor(for: 1, current: distanceAway)?.latitude == distanceAway.latitude && distanceRound.lastShotAnchor(for: 1, current: distanceAway)?.estimated == true)
        distanceRound.swingCandidates?[0].state = .dismissed
        check("dismissed swing restores saved origin", distanceRound.lastShotAnchor(for: 1, current: distanceAway)?.estimated == false)

        let liveStore = RoundStore(storageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        liveStore.startRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart, startHole: 1)
        if var liveRound = liveStore.activeRound, let tee = liveRound.teeCoordinate(for: 1), let pin = liveRound.pinCoordinate(for: 1) {
            let now = Date()
            let gps = GolfLocationSample(point: tee, timestamp: now, accuracy: 5, speed: 0)
            let live = GolfActivityState.snapshot(round: liveRound, fix: gps, now: now)
            check("live activity accurate pin yards", live.yards == Int(tee.yards(to: pin).rounded()) && !live.estimated)
            check("live activity never defaults score to par", live.score == nil)
            check("live activity stale GPS is estimated", GolfActivityState.snapshot(round: liveRound, fix: gps, now: now.addingTimeInterval(31)).estimated)
            var bad = gps; bad.accuracy = 100
            check("live activity rejects inaccurate GPS", GolfActivityState.snapshot(round: liveRound, fix: bad, now: now).estimated)
            bad = gps; bad.point = tee.offset(eastYards: 10000, northYards: 10000)
            check("live activity rejects off-course GPS", GolfActivityState.snapshot(round: liveRound, fix: bad, now: now).estimated)
            liveRound.currentHoleNumber = 2
            let next = GolfActivityState.snapshot(round: liveRound, fix: nil, now: now)
            check("live activity follows hole navigation", next.hole == 2 && next.par == liveRound.hole(2)?.par && next.estimated)
            liveRound.holeScores[0].recordedScore = 5
            liveRound.holeScores[0].isComplete = true
            liveRound.currentHoleNumber = 1
            let scored = GolfActivityState.snapshot(round: liveRound, fix: nil, now: now)
            check("live activity shows confirmed score and total", scored.score == 5 && scored.toPar == "+1" && scored.holesCompleted == 1)
        } else { check("live activity test round", false) }

        if var orientedGreen = liveStore.activeRound?.layout(for: 1) {
            let center = orientedGreen.greenCenter
            orientedGreen.tee = center.offset(eastYards: 0, northYards: -250)
            orientedGreen.path = [orientedGreen.tee, center.offset(eastYards: 100, northYards: 0), center]
            check("green faces final fairway on dogleg", abs(orientedGreen.greenApproachHeading - 270) < 1)
            let originalHeading = orientedGreen.greenApproachHeading
            orientedGreen.pin = center.offset(eastYards: 8, northYards: 8)
            check("moving flag does not rotate green", orientedGreen.greenApproachHeading == originalHeading)
            orientedGreen.path = []
            check("unmapped approach falls back to tee direction", abs(orientedGreen.greenApproachHeading) < 1)
        }

        let reviewDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: reviewDirectory) }
        let reviewStore = RoundStore(storageDirectory: reviewDirectory)
        reviewStore.startRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart, startHole: 1)
        for (label, score, putts, penalties, expected) in [
            ("par five par one putt", 5, 1, 0, 4),
            ("par three birdie one putt", 2, 1, 0, 1),
            ("par four bogey two putts", 5, 2, 0, 3),
            ("penalty is not a physical shot", 5, 1, 1, 3),
            ("hole out without putts", 3, 0, 0, 3),
            ("hole in one", 1, 0, 0, 1)
        ] {
            _ = reviewStore.saveScoreEntry(1, score: score, putts: putts, penalties: penalties)
            check(label + " inferred count", reviewStore.activeRound!.score(for: 1)!.expectedShotCount == expected)
            check(label + " map drafts", reviewStore.suggestedMappedShots(1).count == expected)
        }
        _ = reviewStore.saveScoreEntry(1, score: 5, putts: nil, penalties: 0)
        check("unknown putts do not invent a shot count", reviewStore.activeRound!.score(for: 1)!.expectedShotCount == nil && reviewStore.suggestedMappedShots(1).isEmpty)
        _ = reviewStore.saveScoreEntry(1, score: 5, putts: 1)
        _ = reviewStore.updateHole(1) { $0.dismissedShotSuggestions = 1 }
        check("deliberate draft deletion preserves score implied count", reviewStore.activeRound!.score(for: 1)!.expectedShotCount == 4 && reviewStore.suggestedMappedShots(1).count == 3)
        _ = reviewStore.saveScoreEntry(1, score: 6, putts: 1)
        check("score change recomputes previously dismissed drafts", reviewStore.suggestedMappedShots(1).count == 5)
        _ = reviewStore.saveScoreEntry(1, score: 4, putts: 2)
        let reviewTee = reviewStore.activeRound!.teeCoordinate(for: 1)!
        let reviewPin = reviewStore.activeRound!.pinCoordinate(for: 1)!
        let fairwayOnly = reviewTee.interpolated(to: reviewPin, t: 0.6)
        let reviewTime = Date()
        _ = reviewStore.updateHole(1) { hole in
            hole.locationSamples = [0.0, 5, 10].map { GolfLocationSample(point: fairwayOnly, timestamp: reviewTime.addingTimeInterval($0), accuracy: 4, speed: 0) }
            hole.firstPuttPosition = reviewPin.offset(eastYards: 3, northYards: 0)
        }
        let drafts = reviewStore.suggestedMappedShots(1)
        check("missing tee GPS uses mapped tee", drafts.first?.start == reviewTee)
        check("manual first shot also defaults to tee", reviewStore.suggestedStop(1) == reviewTee)
        check("fairway stop assigned to second shot", drafts.last?.start?.yards(to: fairwayOnly) ?? 999 < 0.01)
        check("review saves all suggested shots atomically", reviewStore.confirmMappedShots(1, suggestions: drafts))
        reviewStore.setCurrentHole(2)
        let reviewReload = RoundStore(storageDirectory: reviewDirectory)
        let persistedReview = reviewReload.activeRound!.score(for: 1)!.shots
        check("next hole preserves every suggested shot", persistedReview.map(\.id) == drafts.map(\.id) && persistedReview.count == 2)
        check("saved review includes actual distances and clubs", persistedReview.allSatisfy { $0.mappedDistanceYards != nil && $0.club != nil && $0.carryYards == nil })
        check("confirming review twice is idempotent", reviewStore.confirmMappedShots(1, suggestions: drafts) && reviewStore.activeRound!.score(for: 1)!.shots.count == 2)
        _ = reviewStore.saveScoreEntry(1, score: 2, putts: 1)
        check("smaller score preserves saved shots for explicit review", reviewStore.activeRound!.score(for: 1)!.shots.count == 2 && reviewStore.suggestedMappedShots(1).isEmpty)
        _ = reviewStore.saveScoreEntry(1, score: 4, putts: 2)
        let third = TrackedShot(number: 3, club: .pitchingWedge, start: fairwayOnly)
        check("add shot after completing hole", reviewStore.addShot(1, third) && reviewStore.activeRound!.score(for: 1)!.shots.count == 3)
        _ = reviewStore.saveScoreEntry(2, score: 4, putts: 2)
        let unsavedDrafts = reviewStore.suggestedMappedShots(2)
        let stateFile = reviewDirectory.appendingPathComponent("golf-state.json")
        try? FileManager.default.removeItem(at: stateFile)
        try? FileManager.default.createDirectory(at: stateFile, withIntermediateDirectories: true)
        check("failed review save blocks navigation", !reviewStore.confirmMappedShots(2, suggestions: unsavedDrafts))
        check("failed review save rolls back shots", reviewStore.activeRound!.score(for: 2)!.shots.isEmpty)
        if var trackingRound = liveStore.activeRound, let hole2 = trackingRound.playLayout(for: 2), let hole3 = trackingRound.playLayout(for: 3) {
            trackingRound.currentHoleNumber = 1
            check("GPS routes hole two while scoring hole one", trackingRound.locationRecordingHole(at: hole2.point(afterTravelling: 170, toward: hole2.pin)) == 2)
            check("GPS routes hole three while scoring hole one", trackingRound.locationRecordingHole(at: hole3.pin) == 3)
            check("GPS outside course is rejected", trackingRound.locationRecordingHole(at: GeoPoint(latitude: 0, longitude: 0)) == nil)
        }

        let trailOrigin = GeoPoint(latitude: 30.67, longitude: -97.7)
        let trailTime = Date()
        func trailSample(_ seconds: Double, _ point: GeoPoint, _ speed: Double = 0) -> GolfLocationSample {
            GolfLocationSample(point: point, timestamp: trailTime.addingTimeInterval(seconds), accuracy: 5, speed: speed)
        }
        let movingTrail = GolfLocationTrail(samples: [trailSample(0, trailOrigin, 5), trailSample(5, trailOrigin.offset(eastYards: 20, northYards: 0), 5), trailSample(30, trailOrigin.offset(eastYards: 40, northYards: 0), 5), trailSample(35, trailOrigin.offset(eastYards: 60, northYards: 0), 5)])
        check("movement lines split across GPS loss", movingTrail.movementPaths.count == 2)
        check("stationary jitter does not draw movement line", GolfLocationTrail(samples: [trailSample(0, trailOrigin), trailSample(5, trailOrigin.offset(eastYards: 1, northYards: 0)), trailSample(10, trailOrigin)]).movementPaths.isEmpty)
        let otherStop = trailOrigin.offset(eastYards: 100, northYards: 0)
        let trailSamples = [trailSample(0, trailOrigin), trailSample(5, trailOrigin.offset(eastYards: 2, northYards: 0)), trailSample(10, trailOrigin),
                            trailSample(15, trailOrigin.offset(eastYards: 30, northYards: 0), 5),
                            trailSample(20, otherStop), trailSample(25, otherStop), trailSample(30, otherStop)]
        let plainTrail = GolfLocationTrail(samples: trailSamples)
        check("GPS dwell consolidates jitter into two stops", plainTrail.stops.count == 2)
        check("Moving GPS remains breadcrumbs", plainTrail.breadcrumbs.count == 1)
        check("New shot prefers latest unused stop", (plainTrail.preferred(excluding: [])?.point.yards(to: otherStop) ?? 100) < 0.01)
        check("Used stop is excluded", plainTrail.preferred(excluding: [otherStop])?.point.yards(to: trailOrigin) ?? 100 < 3)
        check("Nearby drag snaps to stop", plainTrail.nearest(to: otherStop.offset(eastYards: 6, northYards: 0)) != nil)
        check("Distant drag stays free", plainTrail.nearest(to: otherStop.offset(eastYards: 30, northYards: 0)) == nil)
        let watchEvidence = SwingCandidate(roundID: UUID(), hole: 1, timestamp: trailTime.addingTimeInterval(8), latitude: trailOrigin.latitude,
                                          longitude: trailOrigin.longitude, accuracy: 4, locationSource: "watch", peakG: 3, rotation: 5, dwellSeconds: 8)
        let watchTrail = GolfLocationTrail(samples: trailSamples, swings: [watchEvidence])
        check("Watch swing beats later partner stop", watchTrail.preferred(excluding: [])?.point == trailOrigin)
        var dismissedEvidence = watchEvidence; dismissedEvidence.state = .dismissed
        check("Dismissed swing cannot rank a stop", (GolfLocationTrail(samples: trailSamples, swings: [dismissedEvidence]).preferred(excluding: [])?.point.yards(to: otherStop) ?? 100) < 0.01)
        let cachedTrail = GolfLocationTrailCache()
        let firstCached = cachedTrail.resolve(samples: trailSamples, swings: [])
        check("cached trail matches fresh calculation", firstCached == GolfLocationTrail(samples: trailSamples))
        check("cached trail incorporates IMU changes", cachedTrail.resolve(samples: trailSamples, swings: [watchEvidence]) == GolfLocationTrail(samples: trailSamples, swings: [watchEvidence]))
        check("GPS gap cannot imply a stop", GolfLocationTrail(samples: [trailSample(0, trailOrigin), trailSample(60, trailOrigin)]).stops.isEmpty)
        check("Cart movement cannot become a stop", GolfLocationTrail(samples: [trailSample(0, trailOrigin, 4), trailSample(5, trailOrigin, 4), trailSample(10, trailOrigin, 4)]).stops.isEmpty)
        var persistedTrailHole = HoleScore(holeNumber: 1)
        persistedTrailHole.locationSamples = trailSamples
        let trailData = try! JSONEncoder().encode(persistedTrailHole)
        check("Location evidence survives persistence", (try! JSONDecoder().decode(HoleScore.self, from: trailData)).locationSamples == trailSamples)

        var revisionHole = HoleScore(holeNumber: 1)
        let scoreRevision = CompanionRevision.of(revisionHole)
        revisionHole.locationSamples = trailSamples
        check("GPS samples do not invalidate Watch score editor", CompanionRevision.of(revisionHole) == scoreRevision)
        revisionHole.recordedScore = 5
        check("Score changes still invalidate Watch revision", CompanionRevision.of(revisionHole) != scoreRevision)
        let performanceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let performanceStore = RoundStore(storageDirectory: performanceDirectory)
        performanceStore.startRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        for sample in trailSamples { performanceStore.saveLocationSample(sample, hole: 1) }
        check("Score saves after queued GPS writes", performanceStore.saveScoreEntry(1, score: 4, putts: 2))
        performanceStore.load()
        check("Older GPS snapshot cannot overwrite score", performanceStore.activeRound?.score(for: 1)?.recordedScore == 4)
        check("Queued GPS samples survive ordered persistence", performanceStore.activeRound?.score(for: 1)?.locationSamples == trailSamples)
        let normalizedSyncData = try! GolfRecords.assemble(GolfRecords.flatten(performanceStore.cloudData))
        _ = performanceStore.applyCloud(normalizedSyncData, revision: 0, base: normalizedSyncData)
        let syncGeneration = performanceStore.dataGeneration
        let localSyncData = performanceStore.cloudData
        let mirror = try! GolfRecords.flatten(localSyncData)
        let preparedSync = try! GolfPreparedSync.prepare(local: localSyncData, base: localSyncData,
            checkpoint: GolfRecordCheckpoint(cursor: 10, records: mirror), activeID: performanceStore.activeRound?.id)
        check("unchanged sync produces no mutations", preparedSync.changes.isEmpty && !preparedSync.dataChanged)
        let applied = await performanceStore.applyPreparedCloud(preparedSync, expectedGeneration: syncGeneration, owner: nil)
        check("prepared sync persists without changing observed golf data", applied == .applied && performanceStore.dataGeneration == syncGeneration)
        check("cloud checkpoint stays in memory", RoundStore(storageDirectory: performanceDirectory).cloudCheckpoint == nil)
        let canonicalFile = performanceDirectory.appendingPathComponent("golf-state.json")
        let checkpointBytes = try! Data(contentsOf: canonicalFile)
        _ = performanceStore.saveScoreEntry(1, score: 7, putts: 2)
        check("score save does not rewrite cloud checkpoint", (try! Data(contentsOf: canonicalFile)) == checkpointBytes)
        let journalReload = RoundStore(storageDirectory: performanceDirectory)
        check("round journal restores newest score", journalReload.activeRound?.score(for: 1)?.recordedScore == 7)
        check("round journal needs no persisted sync cursor", journalReload.cloudCheckpoint == nil)

        _ = performanceStore.saveScoreEntry(1, score: 5, putts: 2)
        let superseded = await performanceStore.applyPreparedCloud(preparedSync, expectedGeneration: syncGeneration, owner: nil)
        check("edit during reconciliation rejects stale snapshot", superseded == .superseded && performanceStore.activeRound?.score(for: 1)?.recordedScore == 5)
        let wrongOwner = await performanceStore.applyPreparedCloud(preparedSync, expectedGeneration: performanceStore.dataGeneration, owner: UUID())
        check("account switch rejects prepared sync", wrongOwner == .superseded)

        let racingGeneration = performanceStore.dataGeneration
        let racingWrite = Task { @MainActor in
            await performanceStore.applyPreparedCloud(preparedSync, expectedGeneration: racingGeneration, owner: nil)
        }
        await Task.yield()
        _ = performanceStore.saveScoreEntry(1, score: 6, putts: 2)
        _ = await racingWrite.value
        performanceStore.load()
        check("score edited during asynchronous sync IO survives reload", performanceStore.activeRound?.score(for: 1)?.recordedScore == 6)

        try? FileManager.default.removeItem(at: performanceDirectory)

        let spoken = "hit a driver off the tee, slightly towed it, so missed left, then hit a four iron, chunked it, hit sand wedge, good contact, put it to about 10 feet left or right, putt, miss the putt on the high side for a par."
        let result = HoleDictationParser.parse(spoken)
        let clubs = result.shots.map { $0.club }
        print("shots: \(result.shots.map { "\($0.club?.displayName ?? "?") lie=\($0.lie?.label ?? "-") contact=\($0.contact?.label ?? "-") shape=\($0.shape?.label ?? "-") note=\($0.note) leftFt=\($0.leftFeet ?? -1)" }.joined(separator: " | "))")
        print("putts=\(result.puttsMentioned ?? -1) score=\(result.scoreCall ?? "-") leftover=\(result.leftoverNote)")

        check("parses four strokes", result.shots.count >= 4)
        check("driver first", clubs.first == .driver)
        check("driver off the tee", result.shots[0].lie == .tee)
        check("toed / towed → toe", result.shots[0].contact == .toe)
        check("miss direction is not shot shape", result.shots[0].shape == nil && result.shots[0].observations.lateralMiss == .left)
        check("four iron", result.shots.contains { $0.club == .iron4 })
        check("chunked → fat", result.shots.contains { $0.club == .iron4 && $0.contact == .fat })
        check("sand wedge", result.shots.contains { $0.club == .sandWedge })
        check("good contact → pure", result.shots.contains { $0.club == .sandWedge && $0.contact == .pure })
        check("to about 10 feet", result.shots.contains { $0.club == .sandWedge && $0.leftFeet == 10 })
        check("putt is structured", result.shots.contains { $0.club == .putter })
        check("called par", result.scoreCall == "par")
        check("missed putt does not invent a second stroke", result.puttsMentioned == 1)
        check("leftover keeps left or right", result.leftoverNote.contains("left or right"))
        check("leftover keeps high side", result.leftoverNote.contains("high side"))

        let detailed = HoleDictationParser.parse("driver off the heel, carried 240 yards, finished in the rough, missed left and short")
        check("heel is not shank", detailed.shots.first?.contact == .heel)
        check("finish rough is separate from starting lie", detailed.shots.first?.lie == nil && detailed.shots.first?.observations.finish == .rough)
        check("both miss axes survive", detailed.shots.first?.observations.lateralMiss == .left && detailed.shots.first?.observations.depthMiss == .short)
        check("explicit carry captured", detailed.shots.first?.observations.carryYards == 240)
        check("unspecified distance is not carry", HoleDictationParser.parse("driver hit it about 250 yards").shots.first?.observations.carryYards == nil)
        check("approximate travel is not remaining", HoleDictationParser.parseLeftDistance("driver hit it about 250 yards") == nil)
        check("pin high does not invent distance", HoleDictationParser.parseLeftDistance("pin high") == nil)
        let puttingDetail = HoleDictationParser.parse("putter from 20 feet, left to right, missed on the high side, left it short. Then putter from 2 feet, holed it")
        check("individual putts remain separate", puttingDetail.shots.count == 2)
        check("putt break structured", puttingDetail.shots.first?.observations.puttBreak == .leftToRight)
        check("putt high side structured", puttingDetail.shots.first?.observations.puttMissSide == .high)
        check("putt start distance structured", puttingDetail.shots.first?.observations.startingDistanceFeet == 20)
        check("second putt result separate", puttingDetail.shots.last?.observations.holed == true && puttingDetail.shots.last?.observations.puttBreak == nil)
        var encodedShot = TrackedShot(number: 1, club: .driver)
        encodedShot.observations = detailed.shots.first?.observations
        encodedShot.traveledYards = 260
        encodedShot.remainingFeet = 300
        let shotData = try! JSONEncoder().encode(encodedShot)
        check("structured observations round trip", (try! JSONDecoder().decode(TrackedShot.self, from: shotData)) == encodedShot)
        var oldShot = try! JSONSerialization.jsonObject(with: shotData) as! [String: Any]
        for key in ["observations", "traveledYards", "remainingFeet"] { oldShot.removeValue(forKey: key) }
        check("legacy shot still decodes", (try? JSONDecoder().decode(TrackedShot.self, from: JSONSerialization.data(withJSONObject: oldShot))) != nil)

        guard let hole1 = GeorgetownGPS.layouts[1] else {
            print("FAIL missing hole 1 layout")
            exit(1)
        }
        var doglegLayout = hole1
        let bend = hole1.tee.offset(eastYards: 150, northYards: 0)
        doglegLayout.pin = bend.offset(eastYards: 0, northYards: 180)
        doglegLayout.path = [hole1.tee, bend, doglegLayout.pin]
        let fairwayTarget = doglegLayout.initialShotTarget(from: hole1.tee, carryYards: hole1.tee.yards(to: bend))
        check("dogleg initial target follows fairway to bend", fairwayTarget.yards(to: bend) < 2)
        check("dogleg target is not direct midpoint", fairwayTarget.yards(to: hole1.tee.midpoint(to: doglegLayout.pin)) > 50)
        let afterBend = doglegLayout.initialShotTarget(from: bend)
        check("target advances from current position around bend", abs(afterBend.longitude - bend.longitude) < 0.00001 && afterBend.latitude > bend.latitude)
        check("target at pin stays at pin", doglegLayout.initialShotTarget(from: doglegLayout.pin).yards(to: doglegLayout.pin) < 1)
        var noPath = doglegLayout; noPath.path = []
        check("missing fairway path has finite fallback", noPath.initialShotTarget(from: noPath.tee).latitude.isFinite)
        check("standing on the tee", GeorgetownGPS.isStanding(on: 1, at: hole1.tee))
        check("standing on the pin", GeorgetownGPS.isStanding(on: 1, at: hole1.pin))
        // 200 yards left of the playing line — not down the fairway.
        let heading = hole1.headingDegrees
        let rad = (heading + 90) * .pi / 180
        let beside = hole1.tee.offset(eastYards: 200 * sin(rad), northYards: 200 * cos(rad))
        check("200 yards beside the hole is ignored", !GeorgetownGPS.isStanding(on: 1, at: beside))
        if let hole2 = GeorgetownGPS.layouts[2] {
            check("hole 2 tee is not hole 1", !GeorgetownGPS.isStanding(on: 1, at: hole2.tee))
            check("hole 2 tee is hole 2", GeorgetownGPS.isStanding(on: 2, at: hole2.tee))
        }
        check("playPath is tee + optional dogleg + pin", hole1.playPath.count <= 3)
        if let hole4 = GeorgetownGPS.layouts[4] {
            check("dogleg hole keeps a clean path", hole4.playPath.count <= 3)
        }

        let bag = ClubBag.standard
        check("150 yards is 7i in a stock bag", CaddieEngine.recommendClub(for: 150, bag: bag)?.club == .iron7)
        check("90 yards is sand wedge", CaddieEngine.recommendClub(for: 90, bag: bag)?.club == .sandWedge)
        check("label includes the club", CaddieEngine.yardsClubLabel(yards: 150, bag: bag).contains("7i"))
        var shortBag = ClubBag(clubs: [
            ClubBagEntry(club: .driver, carryYards: 250),
            ClubBagEntry(club: .sandWedge, carryYards: 80),
        ])
        shortBag.upsert(.sandWedge, carryYards: 95)
        check("custom SW carry is used", CaddieEngine.recommendClub(for: 90, bag: shortBag)?.club == .sandWedge)
        check("gap in the bag jumps to driver", CaddieEngine.recommendClub(for: 140, bag: shortBag)?.club == .driver)

        let named = ClubBagEntry(club: .hybrid, carryYards: 200, nickname: "4 Hybrid")
        check("nickname is the short label", named.shortLabel == "4 Hybrid")
        check("nickname is the full label", named.fullLabel == "4 Hybrid")
        let namedBag = ClubBag(clubs: [named, ClubBagEntry(club: .putter)])
        check("yards label uses nickname", CaddieEngine.yardsClubLabel(yards: 200, bag: namedBag).contains("4 Hybrid"))

        let legacyJSON = """
        {"id":"00000000-0000-0000-0000-000000000001","club":"iron7","carryYards":155}
        """
        if let legacy = try? JSONDecoder().decode(ClubBagEntry.self, from: Data(legacyJSON.utf8)) {
            check("old bag JSON still decodes", legacy.nickname == nil && legacy.shortLabel == "7i")
        } else {
            check("old bag JSON still decodes", false)
        }

        let origin = GeoPoint(latitude: 30.633, longitude: -97.678)
        let longPin = origin.offset(eastYards: 300, northYards: 0)
        let longTarget = origin.defaultShotTarget(toward: longPin)
        check("default target is ~150y on a long hole", abs(origin.yards(to: longTarget) - 150) < 4)
        let shortPin = origin.offset(eastYards: 100, northYards: 0)
        let shortTarget = origin.defaultShotTarget(toward: shortPin)
        check("default target uses 0.65 on a short hole", abs(origin.yards(to: shortTarget) - 65) < 3)

        var scored = HoleScore(holeNumber: 1)
        scored.applyRecordedScore(score: 4, putts: 2, penalties: 0, fairwayHit: true)
        check("score-first hasScore without shots", scored.hasScore && scored.shots.isEmpty)
        check("gross uses recordedScore", scored.grossScore == 4)
        check("putts use recordedPutts", scored.putts == 2)
        check("marks the hole complete", scored.isComplete)
        check("GIR from recorded par", scored.greenInRegulation(par: 4) == true)
        check("fairway from the sheet", scored.fairwayHit(par: 4) == true)
        scored.shots.append(TrackedShot(number: 1, club: .driver, lie: .tee))
        scored.shots.append(TrackedShot(number: 2, club: .iron7, lie: .rough))
        scored.shots.append(TrackedShot(number: 3, club: .sandWedge, lie: .rough))
        scored.shots.append(TrackedShot(number: 4, club: .putter, lie: .green))
        check("mapping shots does not overwrite recordedScore", scored.grossScore == 4)
        check("mapping shots does not overwrite recordedPutts", scored.putts == 2)
        check("shot trail GIR wins once enough shots exist", scored.greenInRegulation(par: 4) == false)

        var bogey = HoleScore(holeNumber: 2)
        bogey.applyRecordedScore(score: 5, putts: 2, penalties: 1, fairwayHit: false)
        check("bogey is not GIR", bogey.greenInRegulation(par: 4) == false)
        check("missed fairway", bogey.fairwayHit(par: 4) == false)
        check("par 3 skips fairway", bogey.fairwayHit(par: 3) == nil)

        var shotOnly = HoleScore(holeNumber: 3)
        shotOnly.shots = [TrackedShot(number: 1, club: .iron8, lie: .tee)]
        shotOnly.penaltyStrokes = 1
        check("legacy gross is shots + penalties", shotOnly.grossScore == 2)
        check("legacy putts count putter shots", shotOnly.putts == 0)

        check("par 4 chips are 1...8", HoleScore.scoreChipValues(par: 4) == Array(1...8))
        check("par 3 chips start at 1", HoleScore.scoreChipValues(par: 3).first == 1)
        check("current 9 is included", HoleScore.scoreChipValues(par: 4, current: 9).contains(9))

        check("dictated par is the par score", HoleScore.score(fromCall: "par", par: 4) == 4)
        check("dictated birdie", HoleScore.score(fromCall: "birdie", par: 5) == 4)

        do {
            let encoded = try JSONEncoder().encode(HoleScore(holeNumber: 8))
            var obj = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
            obj.removeValue(forKey: "recordedScore")
            obj.removeValue(forKey: "recordedPutts")
            obj.removeValue(forKey: "recordedFairwayHit")
            let stripped = try JSONSerialization.data(withJSONObject: obj)
            let decoded = try JSONDecoder().decode(HoleScore.self, from: stripped)
            check("old hole JSON still decodes", decoded.recordedScore == nil && decoded.holeNumber == 8)
            check("old hole has no score", !decoded.hasScore)
        } catch {
            check("old hole JSON still decodes", false)
        }

        let round = GolfRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        let batch = RoundRecapParser.localDrafts("Hole one, scored five with two putts. Driver missed right. Hole two, par with one putt. Next hole, scored four with two putts and one penalty.", round: round, currentHole: 1)
        let ordinal = RoundRecapParser.segments("On the first I had a five. Second hole I made par. On the third I had a four.", currentHole: 1)
        check("natural ordinal hole references", ordinal.map(\.0) == [1, 2, 3])
        check("par-four description is not a score", HoleDictationParser.parseScoreCall("a par four") == nil)
        check("last score correction wins", HoleDictationParser.parseScoreCall("a birdie putt but finished with bogey") == "bogey")
        check("three holes stay separate", batch.map(\.holeNumber) == [1, 2, 3])
        check("explicit numeric score", batch.first?.score == 5)
        check("spoken par uses correct hole par", batch.count > 1 && batch[1].score == 4)
        check("putt totals belong to their holes", batch.map(\.putts) == [2, 1, 2])
        check("penalty extraction", batch.last?.penalties == 1)
        let correction = RoundRecapParser.localDrafts("Hole four scored six. Hole four actually scored five.", round: round, currentHole: 1)
        check("repeated hole references merge", correction.count == 1 && correction.first?.score == 5)
        let outside = RoundRecapParser.localDrafts("Hole 19 scored five", round: round, currentHole: 1)
        check("out-of-round hole is not selected", outside.first?.selected == false)
        let scoreOnly = HoleDictationParser.parse("par")
        check("score-only recaps are saveable", !scoreOnly.isEmpty)
        let notesOnly = HoleDictationParser.parse("Wind picked up and I felt rushed")
        check("notes-only recap survives", !notesOnly.leftoverNote.isEmpty)
        let summaryFirst = HoleDictationParser.parse("scored five with two putts. Driver missed right.")
        check("score-first summary keeps driver first", summaryFirst.shots.first?.club == .driver && summaryFirst.puttsMentioned == 2)
        check("summary putts are not premature shots", !summaryFirst.shots.contains { $0.club == .putter })
        let quote = "Driver missed right."
        let stated = OpenAIRecap(shots: [OpenAIShotFields(evidence: quote, club: "driver")], puttsMentioned: nil, scoreCall: nil)
        check("supported OpenAI extraction accepted", HoleRecapLLM.grounded(stated, transcript: quote)?.shots.first?.club == .driver)
        let invented = OpenAIRecap(shots: [OpenAIShotFields(evidence: quote, club: "driver", distanceYards: 180)], puttsMentioned: nil, scoreCall: nil)
        check("model distance does not require keyword parser agreement", HoleRecapLLM.grounded(invented, transcript: quote)?.shots.first?.distanceYards == 180)
        let contact = OpenAIRecap(shots: [OpenAIShotFields(evidence: quote, club: "driver", contact: "shank")], puttsMentioned: nil, scoreCall: nil)
        check("model contact is mapped directly", HoleRecapLLM.grounded(contact, transcript: quote)?.shots.first?.contact == .shank)
        let inventedFinish = OpenAIRecap(shots: [OpenAIShotFields(evidence: quote, club: "driver", finish: "water")], puttsMentioned: nil, scoreCall: nil)
        check("model finish is mapped directly", HoleRecapLLM.grounded(inventedFinish, transcript: quote)?.shots.first?.observations.finish == .water)
        let extra = OpenAIRecap(shots: stated.shots + stated.shots, puttsMentioned: nil, scoreCall: nil)
        check("multiple events can share a context quote", HoleRecapLLM.grounded(extra, transcript: quote)?.shots.count == 2)
        check("invented evidence quote rejected", HoleRecapLLM.grounded(stated, transcript: "Par with one putt") == nil)
        let shortRecap = OpenAIRecap(shots: [], puttsMentioned: 1, scoreCall: "par")
        check("summary-only OpenAI recap has no invented clubs", HoleRecapLLM.grounded(shortRecap, transcript: "par with one putt")?.shots.isEmpty == true)
        var analyticsRound = round
        analyticsRound.holeScores[0].recordedScore = 5
        analyticsRound.holeScores[0].isComplete = true
        analyticsRound.holeScores[1].applyRecordedScore(score: 6, putts: 3, penalties: 1, fairwayHit: false)
        analyticsRound.holeScores[2].recordedScore = 2 // Unfinished: excluded from analysis.
        let facts = GolfEvidence(rounds: [analyticsRound])
        check("analysis excludes unfinished holes", facts.completed.count == 2)
        check("unknown putts do not become zero", facts.putting.count == 1 && facts.threePutts == 1)
        check("unknown fairways excluded", facts.fairways.count == 1)
        check("penalty total", facts.penalties == 1)
        check("practice priorities have evidence", !facts.focus.isEmpty && facts.focus.allSatisfy { !$0.evidence.isEmpty })
        check("empty sample has no fake percentage", GolfEvidence.percentage([]) == "—")
        check("scoring baseline uses hole par", facts.averageToPar == 1.5)

        check("benchmark defaults to scratch", BenchmarkLevel.default == .scratch)
        check("unknown handicap falls back to scratch", BenchmarkLevel.suggested(forHandicap: nil) == .scratch)
        check("peer level follows handicap", BenchmarkLevel.suggested(forHandicap: 11) == .hcp10
            && BenchmarkLevel.suggested(forHandicap: 0) == .scratch
            && BenchmarkLevel.suggested(forHandicap: 22) == .hcp20)
        check("peer offset grows with handicap",
            abs(ExpectedStrokes.value(distanceYards: 150, lie: .fairway, level: .hcp10)
                - ExpectedStrokes.value(distanceYards: 150, lie: .fairway, level: .scratch) - (0.25 + 150 * 0.0008)) < 1e-9
                && ExpectedStrokes.value(distanceYards: 150, lie: .fairway, level: .hcp5) < ExpectedStrokes.value(distanceYards: 150, lie: .fairway, level: .hcp10))
        check("scratch putting baseline at ten feet", abs(ExpectedStrokes.value(distanceYards: 10.0 / 3.0, lie: .green, level: .scratch) - 1.6) < 1e-9)
        let textbookTee = StrokesGained.value(startYards: 350, startLie: .tee, endYards: 150, endLie: .fairway, penaltyStrokes: 0, holed: false, level: .scratch)
        check("tee shot SG matches hand calculation", abs(textbookTee - (-0.12)) < 1e-9)
        check("penalty costs a full stroke", abs(StrokesGained.value(startYards: 350, startLie: .tee, endYards: 150, endLie: .fairway, penaltyStrokes: 1, holed: false, level: .scratch) - (textbookTee - 1)) < 1e-9)
        check("holed ten-footer gains", abs(StrokesGained.value(startYards: 10.0 / 3.0, startLie: .green, endYards: 0, endLie: .green, penaltyStrokes: 0, holed: true, level: .scratch) - 0.6) < 1e-9)
        check("par-4 tee shot is off the tee", ShotCategory.classify(shotNumber: 1, par: 4, startLie: .tee, startDistanceYards: 380, isPutt: false) == .offTee)
        check("par-3 tee shot is approach", ShotCategory.classify(shotNumber: 1, par: 3, startLie: .tee, startDistanceYards: 160, isPutt: false) == .approach)
        check("short-game boundary at fifty yards", ShotCategory.classify(shotNumber: 3, par: 4, startLie: .rough, startDistanceYards: 25, isPutt: false) == .aroundGreen)
        check("putter is putting", ShotCategory.classify(shotNumber: 4, par: 4, startLie: .green, startDistanceYards: 4, isPutt: true) == .putting)
        check("empty scope has no SG", Core11.compute(rounds: [], level: .scratch).hasSG == false)
        check("rolling five slices newest first", RollingWindow.last5.slice([analyticsRound, analyticsRound, analyticsRound]).count == 3)

        var sgRound = GolfRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        for index in [0, 1, 4, 7, 8, 10] { // all par 4: pars keep GIR/up-down comparable
            var sgHole = sgRound.holeScores[index]
            sgHole.shots = [
                TrackedShot(number: 1, club: .driver, lie: .tee, distanceToPinBeforeYards: 380, carryYards: 230),
                TrackedShot(number: 2, club: .iron7, lie: .fairway, distanceToPinBeforeYards: 150, carryYards: 150),
                TrackedShot(number: 3, club: .sandWedge, lie: .rough, distanceToPinBeforeYards: 25),
                TrackedShot(number: 4, club: .putter, lie: .green, distanceToPinBeforeYards: 12),
            ]
            sgHole.firstPuttFeet = 36
            sgHole.applyRecordedScore(score: 4, putts: 1, penalties: 0, fairwayHit: true)
            sgRound.holeScores[index] = sgHole
        }
        let sgCore = Core11.compute(rounds: [sgRound], level: .scratch)
        check("valued holes unlock SG", sgCore.hasSG && sgCore.sgTotal.rounds == 1 && sgCore.sgTotal.shots == 24)
        check("hole SG matches hand total", abs(sgCore.sgTotal.total - 6 * 0.22) < 0.05)
        check("category totals reconcile", abs((sgCore.sg(.offTee).total + sgCore.sg(.approach).total + sgCore.sg(.aroundGreen).total + sgCore.sg(.putting).total) - sgCore.sgTotal.total) < 1e-9)
        check("scratch tee shot is neutral", abs(sgCore.sg(.offTee).perRound ?? 99) < 0.01)
        check("GIR band attribution", sgCore.girByBand[.band150to174]?.opportunities == 6 && sgCore.girOverall.value == 0)
        check("up-and-down needs short-game evidence", sgCore.upAndDown.value == 1)
        check("effective distance excludes damage silently", sgCore.effectiveDrivingDistance.map { abs($0 - 230) < 1e-9 } ?? false)
        check("clean drives are not damaging", sgCore.damaging.value == 0 && sgCore.damaging.opportunities == 6)
        let sgPlan = PracticePlan.recommend(core: sgCore, diagnostics: Tier2Diagnostics.compute(rounds: [sgRound], level: .scratch), autopsies: [])
        check("practice targets the SG leak", sgPlan.primary?.category == .approach && sgPlan.secondary?.category == .aroundGreen)
        check("takeaway names the strength", sgPlan.takeaway.contains("Putting"))

        var dblHole = HoleScore(holeNumber: 1)
        var waterTee = TrackedShot(number: 1, club: .driver, lie: .tee, distanceToPinBeforeYards: 380)
        waterTee.observations = ShotObservations(finish: .water, lateralMiss: nil, depthMiss: nil, puttBreak: nil, puttMissSide: nil, holed: nil, carryYards: nil, startingDistanceFeet: nil)
        dblHole.shots = [
            waterTee,
            TrackedShot(number: 2, club: .iron7, lie: .recovery, distanceToPinBeforeYards: 200),
            TrackedShot(number: 3, club: .iron7, lie: .fairway, distanceToPinBeforeYards: 150),
            TrackedShot(number: 4, club: .sandWedge, lie: .rough, distanceToPinBeforeYards: 25),
            TrackedShot(number: 5, club: .putter, lie: .green, distanceToPinBeforeYards: 10),
            TrackedShot(number: 6, club: .putter, lie: .green, distanceToPinBeforeYards: 3),
        ]
        dblHole.applyRecordedScore(score: 7, putts: 3, penalties: 1, fairwayHit: false)
        dblHole.penaltiesByShot = [1: 1]
        let dblResult = DoubleAutopsy.autopsy(hole: dblHole, par: 4, roundID: sgRound.id)
        check("double keeps first error primary", dblResult.primary == .teePenalty && dblResult.secondary.contains(.threePutt))

        var backendGood = GolfRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        backendGood.courseName = "Backend round"
        backendGood.holeScores[0].applyRecordedScore(score: 4, putts: 2, penalties: 0, fairwayHit: true)
        backendGood.status = .finished
        var backendUnreadable = GolfRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        backendUnreadable.courseName = "Newer-writer round"
        backendUnreadable.holeScores[0].applyRecordedScore(score: 4, putts: 2, penalties: 0, fairwayHit: true)
        backendUnreadable.status = .finished
        var pullRecords = try! GolfRecords.flatten(GolfCloudState(rounds: [backendGood, backendUnreadable], bag: .standard, practice: []))
        if let badIndex = pullRecords.firstIndex(where: { $0.kind == "round" && $0.id == backendUnreadable.id }) {
            pullRecords[badIndex].data["status"] = .string("in_progress")
        }
        let pullCheckpoint = GolfRecordCheckpoint(cursor: 9, records: pullRecords)
        let pulled = try! GolfPreparedSync.prepare(local: .empty, base: .empty, checkpoint: pullCheckpoint, activeID: nil)
        check("one unreadable row does not block the pull", pulled.merged.rounds.map(\.id).contains(backendGood.id))
        check("unreadable rows are reported", pulled.undecodableKeys.contains(where: { $0.contains(backendUnreadable.id.uuidString) }))
        let badPullIDs = Set(pullRecords.filter { pulled.undecodableKeys.contains($0.key) }.map(\.id))
        check("unreadable rows are never tombstoned", !pulled.changes.contains(where: { $0.deleted && badPullIDs.contains($0.id) }))
        check("clean pull deletes nothing", !pulled.changes.contains(where: { $0.deleted }))
        let gpsPin = GeoPoint(latitude: 30.66, longitude: -97.67)
        let gpsDrive = TrackedShot(number: 1, club: .driver, lie: .tee, start: gpsPin.offset(eastYards: 0, northYards: 380))
        var explicitDrive = gpsDrive
        explicitDrive.distanceToPinBeforeYards = 100
        check("explicit distance wins over GPS", ShotValuation.startDistance(of: explicitDrive, pin: gpsPin) == 100)
        check("GPS origin derives distance", abs((ShotValuation.startDistance(of: gpsDrive, pin: gpsPin) ?? -1) - 380) < 2)
        check("no position means no distance", ShotValuation.startDistance(of: TrackedShot(number: 1, club: .driver, lie: .tee), pin: gpsPin) == nil)
        var gpsHole = HoleScore(holeNumber: 1)
        gpsHole.pinPosition = HoleScore.PinPosition(x: 0.5, y: 0.62, latitude: gpsPin.latitude, longitude: gpsPin.longitude)
        gpsHole.shots = [gpsDrive, TrackedShot(number: 2, club: .putter, lie: .green, start: gpsPin.offset(eastYards: 0, northYards: 12))]
        gpsHole.applyRecordedScore(score: 3, putts: 1, penalties: 0, fairwayHit: true)
        let gpsValued = ShotValuation.value(hole: gpsHole, par: 4, level: .scratch, pin: gpsPin)
        check("GPS-tracked hole values without typed distances",
            gpsValued.shots.count == 2 && gpsValued.shots.map(\.category) == [.offTee, .putting])
        check("GPS drive SG is sane", abs((gpsValued.shots.first?.sg ?? 99) - 1.08) < 0.1)
        var gpsRound = GolfRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        for index in [0, 1, 4] {
            var hole = HoleScore(holeNumber: gpsRound.holeScores[index].holeNumber)
            hole.pinPosition = HoleScore.PinPosition(x: 0.5, y: 0.62, latitude: gpsPin.latitude, longitude: gpsPin.longitude)
            hole.shots = [
                TrackedShot(number: 1, club: .driver, lie: .tee, start: gpsPin.offset(eastYards: 0, northYards: 380)),
                TrackedShot(number: 2, club: .putter, lie: .green, start: gpsPin.offset(eastYards: 0, northYards: 12)),
            ]
            hole.applyRecordedScore(score: 3, putts: 1, penalties: 0, fairwayHit: true)
            gpsRound.holeScores[index] = hole
        }
        check("GPS-only round lights up the round page", Core11.compute(rounds: [gpsRound], level: .scratch).hasSG)
        // Backend JSON strips nulls: a shot row whose nullable note is missing
        // must still decode instead of vanishing from the round.
        var noteStripHole = HoleScore(holeNumber: 1)
        noteStripHole.applyRecordedScore(score: 4, putts: 2, penalties: 0, fairwayHit: true)
        noteStripHole.shots = [TrackedShot(number: 1, club: .driver, lie: .tee,
            distanceToPinBeforeYards: 380, start: gpsPin.offset(eastYards: 0, northYards: 380))]
        var noteStripRound = GolfRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        noteStripRound.holeScores[0] = noteStripHole
        var noteStripRecords = try! GolfRecords.flatten(GolfCloudState(rounds: [noteStripRound], bag: .standard, practice: []))
        for i in noteStripRecords.indices where noteStripRecords[i].kind == "shot" {
            noteStripRecords[i].data.removeValue(forKey: "note")
        }
        let noteStripped = try! GolfPreparedSync.prepare(local: .empty, base: .empty,
            checkpoint: GolfRecordCheckpoint(cursor: 3, records: noteStripRecords), activeID: nil)
        check("stripped shot note still decodes", noteStripped.merged.rounds.first?.holeScores.first?.shots.count == 1)
        // Duplicate-round regression: consecutive passes over one live round
        // must never mint conflict copies. Pass 1 commits hole 1; pass 2
        // corrects it and scores hole 2 with the base advanced to pass 1's
        // merged state (what advanceCloudBase provides after a commit).
        var liveRound = GolfRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        let liveID = liveRound.id
        let liveBag = ClubBag.standard
        liveRound.holeScores[0].applyRecordedScore(score: 4, putts: 2, penalties: 0, fairwayHit: true)
        let pass1 = try! GolfPreparedSync.prepare(local: GolfCloudState(rounds: [liveRound], bag: liveBag, practice: []),
            base: .empty, checkpoint: GolfRecordCheckpoint(cursor: 0, records: []), activeID: liveID)
        let committedRows = try! GolfRecords.flatten(pass1.merged).map { row -> GolfRecord in
            var r = row; r.revision = 1; return r
        }
        liveRound.holeScores[0].applyRecordedScore(score: 5, putts: 2, penalties: 0, fairwayHit: true)
        liveRound.holeScores[1].applyRecordedScore(score: 4, putts: 1, penalties: 0, fairwayHit: true)
        let pass2 = try! GolfPreparedSync.prepare(local: GolfCloudState(rounds: [liveRound], bag: liveBag, practice: []),
            base: pass1.merged, checkpoint: GolfRecordCheckpoint(cursor: 1, records: committedRows), activeID: liveID)
        let pass2Copies = pass2.merged.rounds.filter { $0.courseName.contains("conflict copy") }
        let pass2Scores = pass2.merged.rounds.first(where: { $0.id == liveID })?.holeScores.filter({ $0.hasScore }).count
        check("live round converges without copies", pass2Copies.isEmpty && pass2.merged.rounds.count == 1 && pass2Scores == 2)
        // Acknowledgements advance the submitted baseline and preserve racing edits.
        let dupeStore = RoundStore(storageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("pinpoint-dupe-test-\(UUID().uuidString)"))
        dupeStore.pastRounds = [liveRound]
        var advancedRound = liveRound
        advancedRound.recap = "edited elsewhere"
        dupeStore.advanceCloudBase(to: GolfCloudState(rounds: [advancedRound], bag: .standard, practice: []), owner: dupeStore.accountID)
        check("base advances on clean generation", dupeStore.cloudBase.rounds.first?.recap == "edited elsewhere")
        dupeStore.pastRounds = [liveRound]
        dupeStore.advanceCloudBase(to: GolfCloudState(rounds: [advancedRound], bag: .standard, practice: []), owner: dupeStore.accountID)
        check("acknowledgement preserves newer local data", dupeStore.cloudBase.rounds.first?.recap == "edited elsewhere" && dupeStore.pastRounds == [liveRound])
        // Timestamps are millisecond-normalized at creation, matching the
        // backend, so sync never sees phantom date diffs.
        let freshShot = TrackedShot(number: 1, club: .driver, lie: .tee)
        check("new entities carry millisecond dates",
            freshShot.timestamp.timeIntervalSinceReferenceDate * 1000 == (freshShot.timestamp.timeIntervalSinceReferenceDate * 1000).rounded()
            && liveRound.startedAt.timeIntervalSinceReferenceDate * 1000 == (liveRound.startedAt.timeIntervalSinceReferenceDate * 1000).rounded())
        // Rows no build can decode stay server-side, untombstoned, with a
        // report naming the problem instead of silent absence.
        var badEnumRecords = noteStripRecords
        for i in badEnumRecords.indices where badEnumRecords[i].kind == "shot" {
            badEnumRecords[i].data["note"] = .string("")
            badEnumRecords[i].data["contact"] = .string("whiffled")
        }
        let badEnum = try! GolfPreparedSync.prepare(local: .empty, base: .empty,
            checkpoint: GolfRecordCheckpoint(cursor: 3, records: badEnumRecords), activeID: nil)
        let badEnumIDs = Set(badEnumRecords.filter { badEnum.undecodableKeys.contains($0.key) }.map(\.id))
        check("undecodable shot is reported with its field",
            (badEnum.skipReport ?? "").contains("shot") && (badEnum.skipReport ?? "").contains("contact"))
        check("reported rows are never tombstoned",
            !badEnum.changes.contains(where: { $0.deleted && badEnumIDs.contains($0.id) }))
        check("offline maps to no-connection advice", GolfSyncFailure.reason(for: URLError(.notConnectedToInternet)).contains("No connection"))
        check("timeout keeps data local", GolfSyncFailure.reason(for: URLError(.timedOut)).contains("saved on this device"))
        struct MissingFunction: Error, CustomStringConvertible {
            var description: String { "Could not find the function public.pull_golf_records in the schema cache" }
        }
        check("missing RPC maps to migrations advice", GolfSyncFailure.reason(for: MissingFunction()).contains("migrations"))
        struct ExpiredSession: Error, CustomStringConvertible {
            var description: String { "AuthApiError: refresh token expired" }
        }
        check("expired session maps to sign-in advice", GolfSyncFailure.reason(for: ExpiredSession()).contains("Sign-in expired"))
        struct Mystery: Error, CustomStringConvertible { var description: String { "quux-7 overloaded" } }
        check("unknown failures stay visible", GolfSyncFailure.reason(for: Mystery()).contains("quux-7"))
        struct StatementTimeout: Error, CustomStringConvertible {
            var description: String { "PostgrestError(code: Optional(\"57014\"), message: \"canceling statement due to statement timeout\")" }
        }
        check("statement timeout maps to retry advice", GolfSyncFailure.reason(for: StatementTimeout()).contains("timed out"))
        check("client timeout maps to retry advice", GolfSyncFailure.reason(for: GolfSyncTimeout.timedOut).contains("Try Sync now"))
        let fastResult = try! await withGolfSyncTimeout(seconds: 30) { 42 }
        check("fast work beats the timeout", fastResult == 42)
        let slowStart = Date()
        do {
            try await withGolfSyncTimeout(seconds: 1) { try await Task.sleep(nanoseconds: 30_000_000_000) }
            check("hung work times out instead of spinning", false)
        } catch {
            check("hung work times out instead of spinning", error is GolfSyncTimeout && Date().timeIntervalSince(slowStart) < 10)
        }

        #if PINPOINT_STORE_SMOKE
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pinpoint-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoundStore(storageDirectory: directory)
        store.startRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        let swingRound = store.activeRound!.id
        var event = SwingCandidate(roundID: swingRound, hole: 1, timestamp: Date(), latitude: nil, longitude: nil,
            accuracy: nil, locationSource: "estimated", peakG: 3, rotation: 6, dwellSeconds: 0)
        let backup = GeoPoint(latitude: 30.66, longitude: -97.67)
        check("phone location backs up missing Watch GPS", store.receiveSwing(event, phonePoint: backup))
        check("phone fallback source retained", store.activeRound?.swingCandidates?.first?.locationSource == "phone")
        check("candidate does not change score", store.activeRound?.score(for: 1)?.hasScore == false)
        check("candidate retries deduplicate", store.receiveSwing(event) && store.activeRound?.swingCandidates?.count == 1)
        check("candidate survives restart", RoundStore(storageDirectory: directory).activeRound?.swingCandidates?.first?.id == event.id)
        check("review requires club", !store.reviewSwing(event.id, holeNumber: 1, club: nil, point: backup, dismiss: false))
        check("practice swing dismisses", store.reviewSwing(event.id, holeNumber: 1, club: nil, point: nil, dismiss: true))
        check("dismissed retry stays dismissed", store.receiveSwing(event) && store.activeRound?.swingCandidates?.first?.state == .dismissed)
        event.id = UUID()
        check("missing all GPS uses default", store.receiveSwing(event))
        check("default marked estimated", store.activeRound?.swingCandidates?.last?.locationSource == "estimated" && store.activeRound?.swingCandidates?.last?.latitude != nil)
        check("confirm to corrected hole", store.reviewSwing(event.id, holeNumber: 9, club: .driver, point: backup, dismiss: false))
        check("confirmed shot uses corrected location", store.activeRound?.score(for: 9)?.shots.first?.start == backup)
        check("estimated shot has no fabricated carry", store.activeRound?.score(for: 9)?.shots.first?.carryYards == nil && store.activeRound?.score(for: 9)?.shots.first?.includeInTrueDistance == false)
        check("confirmed shot cannot duplicate", !store.reviewSwing(event.id, holeNumber: 9, club: .driver, point: backup, dismiss: false))
        event.id = UUID(); event.latitude = 30.65; event.longitude = -97.68; event.accuracy = 8; event.locationSource = "watch"
        check("watch GPS preferred", store.receiveSwing(event, phonePoint: backup) && store.activeRound?.swingCandidates?.last?.latitude == 30.65)
        event.id = UUID(); event.roundID = UUID()
        check("wrong round is not scored", !store.receiveSwing(event))
        check("penalties included in total", store.saveScoreEntry(12, score: 6, putts: 2, penalties: 2))
        check("penalties survive restart", RoundStore(storageDirectory: directory).activeRound?.score(for: 12)?.penaltyStrokes == 2)
        check("invalid penalty rejected", !store.saveScoreEntry(12, score: 3, putts: 2, penalties: 2))
        check("negative penalty rejected", !store.saveScoreEntry(12, score: 6, putts: 2, penalties: -1))
        var gate = SwingDetectionGate()
        for i in 0...120 { _ = gate.sample(time: Double(i) / 50, acceleration: 0.1, rotation: 0.1, stationary: true) }
        _ = gate.sample(time: 2.5, acceleration: 0.8, rotation: 3, stationary: true)
        check("settled swing triggers candidate", gate.sample(time: 2.7, acceleration: 3, rotation: 6, stationary: true))
        check("follow through is suppressed", !gate.sample(time: 2.9, acceleration: 4, rotation: 7, stationary: true))
        var movingGate = SwingDetectionGate()
        for i in 0...120 { _ = movingGate.sample(time: Double(i) / 50, acceleration: 0.1, rotation: 0.1, stationary: false) }
        _ = movingGate.sample(time: 2.5, acceleration: 0.8, rotation: 3, stationary: false)
        check("moving location suppresses swing", !movingGate.sample(time: 2.7, acceleration: 3, rotation: 6, stationary: false))
        var spikeGate = SwingDetectionGate()
        check("isolated spike without setup rejected", !spikeGate.sample(time: 1, acceleration: 4, rotation: 7, stationary: true))
        let greenPin = store.activeRound!.pinCoordinate(for: 1)!
        let firstPutt = greenPin.offset(eastYards: 0, northYards: -6)
        check("first putt position saves", store.saveGreenPosition(1, point: firstPutt, isPin: false))
        check("first putt distance follows coordinates", abs((store.activeRound?.score(for: 1)?.firstPuttFeet ?? 0) - 18) < 0.2)
        check("first putt coordinates survive reload", RoundStore(storageDirectory: directory).activeRound?.score(for: 1)?.firstPuttPosition == firstPutt)
        let movedPin = greenPin.offset(eastYards: 4, northYards: 0)
        check("confirmed pin saves", store.saveGreenPosition(1, point: movedPin, isPin: true))
        check("moving pin updates putt distance", abs((store.activeRound?.score(for: 1)?.firstPuttFeet ?? 0) - firstPutt.yards(to: movedPin) * 3) < 0.1)
        store.updateHole(1) { $0.firstPuttPosition = nil; $0.firstPuttFeet = nil }
        let editable = TrackedShot(number: 1, club: .iron7, start: greenPin)
        store.addShot(1, editable)
        check("direct map drag saves", store.moveShot(1, shot: editable, to: firstPutt))
        check("invalid drag rejected", !store.moveShot(1, shot: editable, to: GeoPoint(latitude: .nan, longitude: 0)))
        check("shot relocation persists", RoundStore(storageDirectory: directory).activeRound?.score(for: 1)?.shots.first(where: { $0.id == editable.id })?.start == firstPutt)
        check("relocation does not fabricate carry", store.activeRound?.score(for: 1)?.shots.first(where: { $0.id == editable.id })?.carryYards == nil)
        let equatorOrigin = GeoPoint(latitude: 0, longitude: 0)
        let nextOrigin = GeoPoint(latitude: 0, longitude: 0.001)
        check("yardage conversion matches surveyed equator baseline", abs(equatorOrigin.yards(to: nextOrigin) - 121.603) < 0.02)
        check("next swing overrides stale landing", TrackedShot(number: 1, end: greenPin).mappedEndpoint(nextStart: nextOrigin, firstPutt: firstPutt, pin: greenPin, putts: 2) == nextOrigin)
        check("approach ends at first putt not cup", editable.mappedEndpoint(nextStart: nil, firstPutt: firstPutt, pin: greenPin, putts: 2) == firstPutt)
        check("unknown first putt does not invent distance to cup", editable.mappedEndpoint(nextStart: nil, firstPutt: nil, pin: greenPin, putts: 2) == nil)
        check("zero putt finish ends at cup", editable.mappedEndpoint(nextStart: nil, firstPutt: nil, pin: greenPin, putts: 0) == greenPin)
        check("explicit landing retained when next origin unknown", TrackedShot(number: 1, end: nextOrigin).mappedEndpoint(nextStart: nil, firstPutt: nil, pin: greenPin, putts: nil) == nextOrigin)
        let scoreBeforeDelete = store.activeRound?.score(for: 1)?.recordedScore
        store.deleteShot(1, id: editable.id)
        check("deleted shot stays deleted on reload", RoundStore(storageDirectory: directory).activeRound?.score(for: 1)?.shots.contains(where: { $0.id == editable.id }) == false)
        check("deleted shot suppresses estimated replacement", RoundStore(storageDirectory: directory).activeRound?.score(for: 1)?.dismissedShotSuggestions == 1)
        check("deleting shot preserves entered score", store.activeRound?.score(for: 1)?.recordedScore == scoreBeforeDelete)
        store.deleteShot(1, id: editable.id)
        check("repeat deletion does not suppress another shot", store.activeRound?.score(for: 1)?.dismissedShotSuggestions == 1)
        let manual = TrackedShot(number: 1, club: .iron7, carryYards: 150)
        store.addShot(1, manual)
        check("review batch saves", store.applyRecaps(batch))
        let count = store.activeRound?.score(for: 1)?.shots.count
        check("repeated voice save succeeds", store.applyRecaps(batch))
        check("repeated voice save does not duplicate shots", store.activeRound?.score(for: 1)?.shots.count == count)
        check("manual shot preserved", store.activeRound?.score(for: 1)?.shots.contains { $0.id == manual.id } == true)
        let voiceDriver = store.activeRound?.score(for: 1)?.shots.first { $0.source == .dictation && $0.club == .driver }
        check("unspoken carry is not fabricated", voiceDriver != nil && voiceDriver?.carryYards == nil && voiceDriver?.includeInTrueDistance == false)
        check("unspoken first-putt distance stays unknown", store.activeRound?.score(for: 1)?.firstPuttFeet == nil)
        _ = store.applyDictation(detailed, to: 3)
        let savedObservation = RoundStore(storageDirectory: directory).activeRound?.score(for: 3)?.shots.last
        check("store persists voice observations", savedObservation?.observations == detailed.shots.first?.observations)
        check("store preserves explicit carry", savedObservation?.carryYards == 240)
        _ = store.applyDictation(HoleDictationParser.parse("driver hit it 250 yards"), to: 3)
        let traveled = RoundStore(storageDirectory: directory).activeRound?.score(for: 3)?.shots.last
        check("travel survives without contaminating carry", traveled?.traveledYards == 250 && traveled?.carryYards == nil && traveled?.includeInTrueDistance == false)
        let reloaded = RoundStore(storageDirectory: directory)
        check("multi-hole scores survive reload", reloaded.activeRound?.score(for: 1)?.recordedScore == 5 && reloaded.activeRound?.score(for: 2)?.recordedScore == 4)
        check("original words survive reload", reloaded.activeRound?.score(for: 1)?.dictateTranscript == batch.first?.transcript)
        check("manual score saves", store.saveScoreEntry(1, score: 6, putts: 3))
        check("score edit keeps mapped shots", store.activeRound?.score(for: 1)?.shots.contains { $0.id == manual.id } == true)
        check("score and putts survive reload", RoundStore(storageDirectory: directory).activeRound?.score(for: 1)?.recordedScore == 6 && RoundStore(storageDirectory: directory).activeRound?.score(for: 1)?.recordedPutts == 3)
        check("score only saves", store.saveScoreEntry(8, score: 4, putts: nil))
        check("untracked putts remain unknown", store.activeRound?.score(for: 8)?.hasKnownPutts == false)
        let beforeInvalidScore = store.activeRound
        check("too many putts rejected", !store.saveScoreEntry(1, score: 2, putts: 3))
        check("zero score rejected", !store.saveScoreEntry(1, score: 0, putts: 0))
        check("negative putts rejected", !store.saveScoreEntry(1, score: 4, putts: -1))
        check("missing hole rejected", !store.saveScoreEntry(99, score: 4, putts: 2))
        check("invalid edit preserves round", store.activeRound == beforeInvalidScore)
        check("hole in one saves with zero putts", store.saveScoreEntry(4, score: 1, putts: 0))
        check("high scores supported", store.saveScoreEntry(5, score: 15, putts: 6))
        let unscored = store.activeRound?.score(for: 6)
        store.setCurrentHole(7)
        check("skip does not complete or score hole", store.activeRound?.score(for: 6) == unscored && unscored?.isComplete == false)
        check("current hole survives reload", RoundStore(storageDirectory: directory).activeRound?.currentHoleNumber == 7)
        for kind in [RoundType.eighteen, .front9, .back9] {
            let start = kind == .back9 ? 14 : 5
            let ordered = GolfRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: kind, scoringMode: .smart, startHole: start)
            check("\(kind) advances in playing order", zip(ordered.holeScores, ordered.holeScores.dropFirst()).allSatisfy { ordered.nextHole(after: $0.holeNumber) == $1.holeNumber })
            check("\(kind) final hole stops", ordered.nextHole(after: ordered.holeScores.last!.holeNumber) == nil)
        }
        let companionHole = store.activeRound!.score(for: 9)!
        let command = CompanionScoreEdit(roundID: store.activeRound!.id, hole: 9, revision: CompanionRevision.of(companionHole), score: 5, putts: 2)
        check("companion score saves", store.applyCompanionEdit(command) == nil)
        let afterCommand = store.activeRound
        check("duplicate companion command is harmless", store.applyCompanionEdit(command) == nil && store.activeRound == afterCommand)
        var staleCommand = command; staleCommand.id = UUID(); staleCommand.score = 6
        check("stale companion edit rejected", store.applyCompanionEdit(staleCommand) != nil && store.activeRound == afterCommand)
        var wrongRound = command; wrongRound.roundID = UUID()
        check("other round command rejected", store.applyCompanionEdit(wrongRound) != nil)
        let encodedCommand = CompanionWire.encode(command)
        check("watch wire format round-trips", CompanionWire.decode(CompanionScoreEdit.self, encodedCommand)?.roundID == command.roundID)
        check("malformed watch command rejected", CompanionWire.decode(CompanionScoreEdit.self, Data("invalid".utf8)) == nil)
        store.setCurrentHole(10)
        let advancing = CompanionScoreEdit(roundID: store.activeRound!.id, hole: 10, revision: CompanionRevision.of(store.activeRound!.score(for: 10)!), score: 3, putts: 2, advance: true)
        check("companion save advances shared hole", store.applyCompanionEdit(advancing) == nil && store.activeRound?.currentHoleNumber == 11)
        check("companion retry does not advance twice", store.applyCompanionEdit(advancing) == nil && store.activeRound?.currentHoleNumber == 11)
        check("par suggests two putts", HoleScore.suggestedPutts(score: 4, par: 4) == 2)
        check("birdie suggests one putt", HoleScore.suggestedPutts(score: 3, par: 4) == 1)
        check("hole in one suggests zero putts", HoleScore.suggestedPutts(score: 1, par: 3) == 0)
        check("logged shots inform putt suggestion", HoleScore.suggestedPutts(score: 5, par: 4, penalties: 1, nonPuttingShots: 3) == 1)
        check("stroke penalties save", store.saveScoreEntry(14, score: 6, putts: 2, penalties: 2, penaltiesByShot: [1: 2]))
        check("stroke penalties survive reload", RoundStore(storageDirectory: directory).activeRound?.score(for: 14)?.penaltiesByShot == [1: 2])
        check("penalty assignments cannot exceed total", !store.saveScoreEntry(14, score: 6, putts: 2, penalties: 1, penaltiesByShot: [1: 2]))
        check("penalty must belong to a physical shot", !store.saveScoreEntry(14, score: 4, putts: 2, penalties: 1, penaltiesByShot: [2: 1]))
        _ = store.saveScoreEntry(15, score: 4, putts: 2)
        let mapPin = store.activeRound!.pinCoordinate(for: 15)!
        let approachStart = mapPin.offset(eastYards: 0, northYards: -150)
        let firstShot = TrackedShot(number: 1, start: mapPin.offset(eastYards: 0, northYards: -330), includeInTrueDistance: false)
        let approachShot = TrackedShot(number: 2, start: approachStart, includeInTrueDistance: false)
        _ = store.moveShot(15, shot: firstShot, to: firstShot.start!)
        _ = store.moveShot(15, shot: approachShot, to: approachStart)
        _ = store.saveGreenPosition(15, point: mapPin.offset(eastYards: 0, northYards: -6), isPin: false)
        let mappedApproach = store.activeRound!.score(for: 15)!.shots.first { $0.id == approachShot.id }!
        check("mapped distance automatically populated", abs((mappedApproach.mappedDistanceYards ?? 0) - 144) < 0.5)
        check("club automatically suggested", mappedApproach.club != nil && mappedApproach.clubWasSuggested == true)
        check("mapped distance does not become carry", mappedApproach.carryYards == nil)
        let movedApproach = approachStart.offset(eastYards: 0, northYards: 30)
        _ = store.moveShot(15, shot: mappedApproach, to: movedApproach)
        let mapShots = store.activeRound!.score(for: 15)!.shots
        check("moving shot updates its actual distance", abs((mapShots[1].mappedDistanceYards ?? 0) - 114) < 0.5)
        check("moving shot updates previous distance", abs((mapShots[0].mappedDistanceYards ?? 0) - 210) < 0.5)
        check("actual distance survives reload", RoundStore(storageDirectory: directory).activeRound?.score(for: 15)?.shots[1].mappedDistanceYards == mapShots[1].mappedDistanceYards)
        check("short chip suggestion stays a non-putt", CaddieEngine.suggestedShotClub(for: 6, bag: store.clubBag)?.isPutter == false)
        var chosenApproach = store.activeRound!.score(for: 15)!.shots[1]
        chosenApproach.club = .iron9; chosenApproach.clubWasSuggested = false
        store.updateShot(15, chosenApproach)
        _ = store.moveShot(15, shot: chosenApproach, to: approachStart)
        check("moving preserves explicitly selected club", store.activeRound!.score(for: 15)!.shots[1].club == .iron9)
        let snapPin = GeoPoint(latitude: 30, longitude: -97)
        let farOrigin = snapPin.offset(eastYards: 0, northYards: -200)
        check("planner snaps target near flag", RangefinderSnap.isDirect(origin: farOrigin, target: snapPin.offset(eastYards: 10, northYards: 0), pin: snapPin, wasDirect: false))
        check("planner keeps snap through small movements", RangefinderSnap.isDirect(origin: farOrigin, target: snapPin.offset(eastYards: 20, northYards: 0), pin: snapPin, wasDirect: true))
        check("dragging away restores two lines", !RangefinderSnap.isDirect(origin: farOrigin, target: snapPin.offset(eastYards: 30, northYards: 0), pin: snapPin, wasDirect: true))
        check("near-green player gets direct flag line", RangefinderSnap.isDirect(origin: snapPin.offset(eastYards: 30, northYards: 0), target: farOrigin, pin: snapPin, wasDirect: false))
        check("ordinary fairway target remains two legs", !RangefinderSnap.isDirect(origin: farOrigin, target: snapPin.offset(eastYards: 0, northYards: -100), pin: snapPin, wasDirect: false))
        let advancingLayout = GeorgetownGPS.layout(for: 1)!
        let openingTarget = advancingLayout.initialShotTarget(from: advancingLayout.tee, carryYards: 150, par: 4)
        func advanced(_ origin: GeoPoint, _ target: GeoPoint) -> GeoPoint {
            RangefinderSnap.advancingTarget(origin: origin, target: target, pin: advancingLayout.pin, layout: advancingLayout)
        }
        check("tee retains fairway planning target", advanced(advancingLayout.tee, openingTarget) == openingTarget)
        check("reaching fairway target advances to green", advanced(openingTarget, openingTarget) == advancingLayout.pin)
        let beyondTarget = advancingLayout.point(afterTravelling: advancingLayout.project(openingTarget).along + 40, toward: advancingLayout.pin)
        check("passing target advances to green", advanced(beyondTarget, openingTarget) == advancingLayout.pin)
        check("rough beside target advances along corridor", advanced(openingTarget.offset(eastYards: 25, northYards: 0), openingTarget) == advancingLayout.pin)
        check("GPS jitter cannot restore consumed target", advanced(openingTarget.offset(eastYards: 2, northYards: 0), advancingLayout.pin) == advancingLayout.pin)
        check("off-course fix does not advance target", advanced(openingTarget.offset(eastYards: 500, northYards: 0), openingTarget) == openingTarget)
        let futureTarget = advancingLayout.point(afterTravelling: advancingLayout.project(openingTarget).along + 80, toward: advancingLayout.pin)
        check("new forward layup remains available", advanced(openingTarget, futureTarget) == futureTarget)

        var dogleg = advancingLayout
        let corner = dogleg.tee.offset(eastYards: 200, northYards: 0)
        dogleg.pin = dogleg.tee.offset(eastYards: 200, northYards: 200)
        dogleg.path = [dogleg.tee, corner, dogleg.pin]
        let aroundBend = corner.offset(eastYards: 0, northYards: 50)
        check("dogleg progress consumes target around bend", RangefinderSnap.advancingTarget(origin: aroundBend, target: corner, pin: dogleg.pin, layout: dogleg) == dogleg.pin)
        let autoTarget = advanced(beyondTarget, openingTarget)
        let autoLegs = RangefinderSnap.legs(origin: beyondTarget, target: autoTarget, pin: advancingLayout.pin,
            direct: RangefinderSnap.isDirect(origin: beyondTarget, target: autoTarget, pin: advancingLayout.pin, wasDirect: false))
        check("advanced planner has exactly one distance label", autoLegs.count == 1 && autoLegs.first?.id == .flag)

        let driverTarget = dogleg.initialShotTarget(from: dogleg.tee, carryYards: 240, par: 4)
        check("opening target matches driver distance through dogleg", abs(dogleg.tee.yards(to: driverTarget) - 240) < 0.1)
        check("driver target stays on mapped fairway", dogleg.distanceToCorridor(driverTarget) < 0.1)
        let shorterDriver = dogleg.initialShotTarget(from: dogleg.tee, carryYards: 180, par: 4)
        check("shorter driver changes opening target", abs(dogleg.tee.yards(to: shorterDriver) - 180) < 0.1)
        check("reachable green uses direct target", dogleg.initialShotTarget(from: dogleg.tee, carryYards: 320, par: 4) == dogleg.pin)
        check("par three remains direct regardless of driver", dogleg.initialShotTarget(from: dogleg.tee, carryYards: 180, par: 3) == dogleg.pin)
        check("invalid driver distance uses stock fallback", dogleg.initialShotTarget(from: dogleg.tee, carryYards: .nan, par: 4) == dogleg.initialShotTarget(from: dogleg.tee, carryYards: GolfClub.driver.stockYards, par: 4))

        let directLegs = RangefinderSnap.legs(origin: farOrigin, target: snapPin.offset(eastYards: 10, northYards: 0), pin: snapPin, direct: true)
        check("snapped planner has exactly one distance", directLegs.count == 1 && directLegs[0].id == .flag)
        check("snapped distance runs all the way to flag", directLegs[0].start == farOrigin && directLegs[0].end == snapPin)
        check("layup restores both distance labels", RangefinderSnap.legs(origin: farOrigin, target: snapPin.offset(eastYards: 50, northYards: 0), pin: snapPin, direct: false).count == 2)
        check("par three defaults to flag", doglegLayout.initialShotTarget(from: doglegLayout.tee, par: 3) == doglegLayout.pin)
        check("par four retains fairway target", doglegLayout.initialShotTarget(from: doglegLayout.tee, carryYards: 150, par: 4) != doglegLayout.pin)
        var trailHole = store.activeRound!.score(for: 15)!
        let fixedTee = store.activeRound!.teeCoordinate(for: 15)!
        let trail = trailHole.recordedShotLegs(tee: fixedTee, pin: mapPin)
        check("recorded shots produce connecting lines", trail.contains { $0.start == trailHole.shots[0].start && $0.end == trailHole.shots[1].start })
        check("tee does not follow added shots", store.activeRound!.teeCoordinate(for: 15) == fixedTee)
        trailHole.shots[0].start = nil
        check("missing first origin uses fixed tee", trailHole.shotOrigin(at: 0, tee: fixedTee) == fixedTee)
        trailHole.shots = [TrackedShot(number: 1, club: .driver)]
        trailHole.firstPuttPosition = nil; trailHole.recordedPutts = nil
        check("unknown landing is not fabricated from club distance", trailHole.recordedShotLegs(tee: fixedTee, pin: mapPin).isEmpty)
        let savedTee = store.activeRound!.teeCoordinate(for: 16)!
        let firstPlaced = TrackedShot(number: 1, club: .driver, start: savedTee)
        let secondPlaced = TrackedShot(number: 2, club: .gapWedge, start: savedTee.offset(eastYards: 10, northYards: 200))
        check("save second estimated shot first", store.moveShot(16, shot: secondPlaced, to: secondPlaced.start!))
        check("save first estimated shot afterwards", store.moveShot(16, shot: firstPlaced, to: savedTee))
        let reloadedShots = RoundStore(storageDirectory: directory).activeRound!.score(for: 16)!.shots
        check("first placed shot survives reload with identity", reloadedShots.first?.id == firstPlaced.id && reloadedShots.first?.start == savedTee)
        check("second placed shot retains number", reloadedShots.last?.id == secondPlaced.id && reloadedShots.last?.number == 2)
        var editedFirst = reloadedShots[0]
        editedFirst.start = savedTee.offset(eastYards: 4, northYards: 0)
        check("first shot editor save succeeds", store.updateShot(16, editedFirst))
        check("first edited shot survives reload", RoundStore(storageDirectory: directory).activeRound!.score(for: 16)!.shots[0].start == editedFirst.start)
        check("saving first shot preserves tee", store.activeRound!.teeCoordinate(for: 16) == savedTee)
        let lifecycleDirectory = directory.appendingPathComponent("lifecycle")
        let lifecycle = RoundStore(storageDirectory: lifecycleDirectory)
        lifecycle.startRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        _ = lifecycle.saveScoreEntry(1, score: 5, putts: 2)
        let partialID = lifecycle.activeRound!.id
        check("partial cannot be saved as nine", !lifecycle.finishRound(saveAsNine: true))
        check("save unfinished round", lifecycle.finishRound(recap: "Rain stopped play"))
        let partialReload = RoundStore(storageDirectory: lifecycleDirectory)
        check("unfinished saved in history", partialReload.pastRounds.first?.status == .unfinished && partialReload.pastRounds.first?.id == partialID)
        check("unfinished preserves score and recap", partialReload.pastRounds.first?.score(for: 1)?.recordedScore == 5 && partialReload.pastRounds.first?.recap == "Rain stopped play")
        check("saved unfinished is no longer active", partialReload.activeRound == nil)
        lifecycle.startRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart, startHole: 10)
        for number in 10...18 { _ = lifecycle.saveScoreEntry(number, score: 4, putts: 2) }
        let staleActive = lifecycle.activeRound!
        check("nine hole finish available", staleActive.nineHoleNumbers?.count == 9)
        check("save back nine from eighteen", lifecycle.finishRound(saveAsNine: true))
        let savedNine = lifecycle.pastRounds[0]
        check("nine is completed with correct totals", savedNine.status == .finished && savedNine.roundType == .back9 && savedNine.totalGross == 36 && savedNine.playedHoleScores.count == 9)
        check("nine keeps original raw holes", savedNine.holeScores.count == 18)
        check("nine stats cover nine holes", lifecycle.stats(for: [savedNine]).holesPlayed == 9)
        try? JSONEncoder().encode(staleActive).write(to: lifecycleDirectory.appendingPathComponent("active-round.json"), options: [.atomic])
        check("archived round cannot resurrect after interrupted cleanup", RoundStore(storageDirectory: lifecycleDirectory).activeRound == nil)
        lifecycle.startRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .front9, scoringMode: .smart)
        let historyBeforeDelete = lifecycle.pastRounds
        check("discard active round", lifecycle.discardActiveRound())
        let afterDiscard = RoundStore(storageDirectory: lifecycleDirectory)
        check("discard persists without touching history", afterDiscard.activeRound == nil && afterDiscard.pastRounds == historyBeforeDelete)
        lifecycle.startRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .front9, scoringMode: .smart)
        let beforeEndFailure = lifecycle.activeRound
        let historyFile = lifecycleDirectory.appendingPathComponent("golf-state.json")
        try? FileManager.default.removeItem(at: historyFile)
        try? FileManager.default.createDirectory(at: historyFile, withIntermediateDirectories: true)
        check("failed finish reports error", !lifecycle.finishRound())
        check("failed finish keeps active round and history", lifecycle.activeRound == beforeEndFailure && lifecycle.pastRounds == historyBeforeDelete)
        let cloudDirectory = directory.appendingPathComponent("cloud-accounts")
        let deviceA = RoundStore(storageDirectory: cloudDirectory)
        deviceA.startRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        _ = deviceA.saveScoreEntry(1, score: 4, putts: 2)
        let guestID = deviceA.activeRound!.id
        let accountA = UUID(), accountB = UUID()
        check("first account adopts existing local round", deviceA.selectAccount(accountA) && deviceA.activeRound?.id == guestID)
        check("default guest bag does not duplicate cloud clubs", deviceA.clubBag.clubs.isEmpty)
        check("signout hides account rounds", deviceA.selectAccount(nil) && deviceA.activeRound == nil && deviceA.pastRounds.isEmpty)
        check("second account is isolated", deviceA.selectAccount(accountB) && deviceA.cloudData.rounds.isEmpty)
        check("returning account restores offline cache", deviceA.selectAccount(accountA) && deviceA.activeRound?.id == guestID)
        let cloudBase = deviceA.cloudData
        check("initial cloud checkpoint saves", deviceA.applyCloud(cloudBase, revision: 1, base: cloudBase))
        let deviceB = RoundStore(storageDirectory: directory.appendingPathComponent("second-device"))
        _ = deviceB.selectAccount(accountA)
        check("second device downloads round", deviceB.applyCloud(cloudBase, revision: 1, base: cloudBase) && deviceB.activeRound?.id == guestID)
        _ = deviceA.saveScoreEntry(2, score: 5, putts: 2)
        _ = deviceB.saveScoreEntry(3, score: 3, putts: 1)
        let combined = try! GolfCloudMerge.merge(base: cloudBase, local: deviceA.cloudData, remote: deviceB.cloudData)
        check("concurrent different holes merge", combined.rounds.count == 1 && combined.rounds[0].score(for: 2)?.recordedScore == 5 && combined.rounds[0].score(for: 3)?.recordedScore == 3)
        _ = deviceA.saveScoreEntry(1, score: 5, putts: 2)
        _ = deviceB.saveScoreEntry(1, score: 6, putts: 2)
        let collision = try! GolfCloudMerge.merge(base: cloudBase, local: deviceA.cloudData, remote: deviceB.cloudData)
        check("conflicting scores preserve both versions", collision.rounds.count == 2 && collision.rounds.contains { $0.courseName.contains("conflict copy") && $0.score(for: 1)?.recordedScore == 5 } && collision.rounds.contains { $0.id == guestID && $0.score(for: 1)?.recordedScore == 6 })
        let repeatedCollision = try! GolfCloudMerge.merge(base: cloudBase, local: deviceA.cloudData, remote: deviceB.cloudData)
        check("conflict retries keep stable copy identities", Set(collision.rounds.map(\.id)) == Set(repeatedCollision.rounds.map(\.id)))
        var localWithCopy = deviceA.cloudData
        localWithCopy.rounds += collision.rounds.filter { $0.id != guestID }
        let dedupedCollision = try! GolfCloudMerge.merge(base: cloudBase, local: localWithCopy, remote: deviceB.cloudData)
        check("existing conflict copy is not duplicated", dedupedCollision.rounds.count == 2)
        var movingA = cloudBase, movingB = cloudBase
        movingA.rounds[0].currentHoleNumber = 2; movingB.rounds[0].currentHoleNumber = 3
        let mergeTee = movingA.rounds[0].teeCoordinate(for: 1)!
        movingA.rounds[0].holeScores[0].locationSamples = [GolfLocationSample(point: mergeTee, timestamp: Date(timeIntervalSince1970: 100), accuracy: 4, speed: 0)]
        movingB.rounds[0].holeScores[0].locationSamples = [GolfLocationSample(point: mergeTee.offset(eastYards: 20, northYards: 0), timestamp: Date(timeIntervalSince1970: 110), accuracy: 5, speed: 3)]
        let mergedMovement = try! GolfCloudMerge.merge(base: cloudBase, local: movingA, remote: movingB)
        check("concurrent navigation and GPS do not create round copies", mergedMovement.rounds.count == 1 && mergedMovement.rounds[0].holeScores[0].locationSamples?.count == 2)
        var weatherA = cloudBase, weatherB = cloudBase
        weatherA.rounds[0].windMph = 8; weatherB.rounds[0].windMph = 12
        check("weather refresh does not duplicate rounds", (try! GolfCloudMerge.merge(base: cloudBase, local: weatherA, remote: weatherB)).rounds.count == 1)
        let movementAgain = try! GolfCloudMerge.merge(base: cloudBase, local: mergedMovement, remote: movingB)
        check("GPS merge retries do not duplicate samples", movementAgain.rounds.count == 1 && movementAgain.rounds[0].holeScores[0].locationSamples?.count == 2)
        let deleteStore = RoundStore(storageDirectory: directory.appendingPathComponent("delete-round-test"))
        deleteStore.startRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        let deleteID = deleteStore.activeRound!.id
        _ = deleteStore.saveScoreEntry(1, score: 4, putts: 2)
        _ = deleteStore.finishRound()
        let beforeDeletion = deleteStore.cloudData
        check("saved round can be deleted", deleteStore.deleteRound(deleteID) && deleteStore.pastRounds.isEmpty)
        check("round deletion survives restart", RoundStore(storageDirectory: directory.appendingPathComponent("delete-round-test")).cloudData.rounds.isEmpty)
        let deletionChanges = try! GolfRecords.changes(local: deleteStore.cloudData, mirror: GolfRecords.flatten(beforeDeletion))
        check("round deletion generates synced tombstones", deletionChanges.contains { $0.kind == "round" && $0.id == deleteID && $0.deleted })
        _ = deviceA.discardActiveRound()
        let deletion = try! GolfCloudMerge.merge(base: cloudBase, local: deviceA.cloudData, remote: deviceB.cloudData)
        check("offline deletion does not resurrect stale round", deletion.rounds.isEmpty)
        let practice = PracticeSession(focus: "Putting", made: 5, attempts: 10, note: "Test")
        check("practice saved in account", deviceA.savePracticeSession(practice))
        let accountReload = RoundStore(storageDirectory: cloudDirectory)
        _ = accountReload.selectAccount(accountA)
        check("practice and pending deletion survive restart", accountReload.practiceSessions.contains(practice) && accountReload.cloudData.rounds.isEmpty && accountReload.cloudBase.rounds.count == 1)
        check("sync comparison ignores ordering", GolfCloudState(rounds: collision.rounds, bag: .standard, practice: []) != GolfCloudState(rounds: [], bag: ClubBag(clubs: []), practice: []))
        var reordered = collision; reordered.rounds.reverse()
        check("equivalent reordered cloud state avoids repeat uploads", reordered == collision)
        check("fresh devices share default club IDs", GolfCloudState.initialBag == GolfCloudState.initialBag)
        var shotBase = cloudBase
        shotBase.rounds[0].holeScores[0].shots = [TrackedShot(number: 1, club: .driver, start: savedTee)]
        var shotLocal = shotBase, shotRemote = shotBase
        shotLocal.rounds[0].holeScores[0].shots[0].start = firstPutt
        shotRemote.rounds[0].holeScores[0].shots[0].note = "Toe contact"
        let shotMerge = try! GolfCloudMerge.merge(base: shotBase, local: shotLocal, remote: shotRemote)
        check("same shot independent location and detail edits merge", shotMerge.rounds.count == 1 && shotMerge.rounds[0].holeScores[0].shots[0].start == firstPutt && shotMerge.rounds[0].holeScores[0].shots[0].note == "Toe contact")
        let flat = try! GolfRecords.flatten(shotMerge)
        let restored = try! GolfRecords.assemble(flat)
        check("relational round trip preserves holes and first shot", try! GolfRecords.flatten(restored) == flat)
        check("unchanged records need no upload", try! GolfRecords.changes(local: restored, mirror: flat).isEmpty)
        var moved = restored
        moved.rounds[0].holeScores[0].shots[0].note = "Changed one shot"
        let shotChanges = try! GolfRecords.changes(local: moved, mirror: flat)
        check("one shot edit only uploads one shot row", shotChanges.count == 1 && shotChanges[0].kind == "shot")
        var dead = flat.first { $0.kind == "round" }!; dead.deleted = true
        let pruned = try! GolfRecords.removingTombstones(from: restored, mirror: [dead])
        check("tombstone removes round from stale first-sync cache", pruned.rounds.isEmpty)
        var copied = restored.rounds[0]; copied.id = UUID()
        var withCopy = restored; withCopy.rounds.append(copied)
        let copiedFlat = try! GolfRecords.flatten(withCopy)
        check("conflict copies keep distinct composite shot keys", Set(copiedFlat.map(\.key)).count == copiedFlat.count)
        let checkpointDirectory = directory.appendingPathComponent("record-checkpoint")
        let cache = RoundStore(storageDirectory: checkpointDirectory)
        let checkpoint = GolfRecordCheckpoint(cursor: 42, records: flat.map { $0.key == dead.key ? dead : $0 })
        check("record checkpoint saves atomically with local data", cache.applyCloud(restored, revision: 42, base: restored, checkpoint: checkpoint))
        let reloadedCache = RoundStore(storageDirectory: checkpointDirectory)
        check("history mirror and tombstones are not persisted", reloadedCache.cloudCheckpoint == nil && reloadedCache.pastRounds.isEmpty)

        var completedState = restored
        completedState.rounds[0].status = .finished
        completedState.bag = GolfCloudState.initialBag
        let tolerantState = GolfRecords.assembleTolerant(try! GolfRecords.flatten(completedState)).state
        check("cloud reader attaches each shot to its parent hole", tolerantState.rounds[0].holeScores[0].shots == completedState.rounds[0].holeScores[0].shots)
        let cleanCache = GolfLocalState(data: completedState, activeID: nil, base: completedState).localCache()
        check("acknowledged history is absent from disk", cleanCache.data.rounds.isEmpty && cleanCache.base.rounds.isEmpty && cleanCache.checkpoint == nil)
        var pendingState = completedState
        pendingState.rounds[0].recap = "Offline correction"
        let pendingCache = GolfLocalState(data: pendingState, activeID: nil, base: completedState).localCache()
        check("unsent history correction keeps its merge base", pendingCache.data.rounds == pendingState.rounds && pendingCache.base.rounds == completedState.rounds)
        let pendingDelete = GolfLocalState(data: .empty, activeID: nil, base: completedState).localCache()
        check("pending deletion survives without keeping visible history", pendingDelete.data.rounds.isEmpty && pendingDelete.base.rounds == completedState.rounds)
        let currentRecords = try! GolfRecords.flatten(completedState)
        let freshRequest = try! GolfPreparedSync.prepare(local: cleanCache.data, base: cleanCache.base,
            checkpoint: GolfRecordCheckpoint(cursor: 1, records: currentRecords), activeID: nil)
        check("fresh cloud response restores history without upload or disk mirror", (try! GolfRecords.flatten(freshRequest.merged)) == currentRecords && freshRequest.changes.isEmpty && (try! JSONDecoder().decode(GolfLocalState.self, from: freshRequest.encodedState)).data.rounds.isEmpty)

        if let path = ProcessInfo.processInfo.environment["PINPOINT_RECORD_RESPONSE"],
           let response = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            let checkpoint = try! JSONDecoder().decode(GolfRecordCheckpoint.self, from: response)
            let decoded = try! GolfRecords.assemble(checkpoint.records)
            check("database records decode into real app models", decoded.rounds.count == 1 && decoded.rounds[0].holeScores.count == 18 && decoded.rounds[0].holeScores[0].shots.count == 1)
            check("database round trip has no repeated record writes", try! GolfRecords.changes(local: decoded, mirror: checkpoint.records).isEmpty)
            let prepared = try! GolfPreparedSync.prepare(local: decoded, base: decoded, checkpoint: checkpoint, activeID: decoded.rounds.first?.id)
            check("authenticated checkpoint needs no repeat upload after background merge", prepared.changes.isEmpty && !prepared.dataChanged)

        }
        if let path = ProcessInfo.processInfo.environment["PINPOINT_SYNC_FIXTURE"] {
            var fixture = shotMerge
            fixture.bag = GolfCloudState.initialBag
            fixture.practice = [practice]
            try! JSONEncoder().encode(GolfRecords.changes(local: fixture, mirror: [])).write(to: URL(fileURLWithPath: path + ".changes"))
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try! encoder.encode(fixture).write(to: URL(fileURLWithPath: path), options: [.atomic])
        }
        let natural = "The big stick peeled right off the outer edge. Actually that was on two. On one I had par with one putt."
        let interpreted = OpenAIRoundRecap(holes: [
            OpenAIHoleRecap(holeNumber: 2, evidence: natural, score: 5, putts: 2, penalties: nil, fairwayHit: false, scoreCall: nil,
                shots: [OpenAIShotFields(evidence: natural, club: "driver", contact: "toe", shape: "fade", finish: "rough")], notes: "Hole correction applied", warnings: []),
            OpenAIHoleRecap(holeNumber: 1, evidence: natural, score: 4, putts: 1, penalties: nil, fairwayHit: nil, scoreCall: "par", shots: [], notes: "", warnings: [])
        ], warnings: [])
        let modelDrafts = try! HoleRecapLLM.drafts(interpreted, transcript: natural, round: round)
        check("LLM decides colloquial shot and corrected hole without parser agreement", modelDrafts[1].result.shots.first?.contact == .toe && modelDrafts[1].result.shots.first?.shape == .fade && modelDrafts[1].holeNumber == 2)
        check("LLM scores and putts preserved without regex overrides", modelDrafts[0].score == 4 && modelDrafts[0].putts == 1 && modelDrafts[1].score == 5)
        check("unknown model fields stay empty in review", modelDrafts[1].result.shots.first?.lie == nil && modelDrafts[1].result.shots.first?.distanceYards == nil)
        let aiStore = RoundStore(storageDirectory: directory.appendingPathComponent("llm-review"))
        aiStore.startRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        check("confirmed LLM draft saves", aiStore.applyRecaps(modelDrafts))
        check("summary totals do not synthesize shots during confirmation", aiStore.activeRound?.score(for: 1)?.shots.isEmpty == true && aiStore.activeRound?.score(for: 1)?.recordedPutts == 1)
        check("saved LLM shot fields survive confirmation", aiStore.activeRound?.score(for: 2)?.shots.count == 1 && aiStore.activeRound?.score(for: 2)?.shots.first?.contact == .toe && aiStore.activeRound?.score(for: 2)?.shots.first?.lieWasInferred == true)
        var invalidModel = interpreted
        invalidModel.holes[0].shots[0].distanceYards = -2
        check("invalid LLM distance rejected by range only", (try? HoleRecapLLM.drafts(invalidModel, transcript: natural, round: round)) == nil)
        invalidModel = interpreted; invalidModel.holes[0].shots[0].club = "made up club"
        check("unknown LLM club rejected by enum only", (try? HoleRecapLLM.drafts(invalidModel, transcript: natural, round: round)) == nil)
        invalidModel = interpreted; invalidModel.holes[0].score = 1; invalidModel.holes[0].putts = 3
        let contradictory = try! HoleRecapLLM.drafts(invalidModel, transcript: natural, round: round)
        check("contradictory model totals preserved and flagged for review", contradictory[1].score == 1 && contradictory[1].putts == 3 && !contradictory[1].result.warnings.isEmpty)
        if let path = ProcessInfo.processInfo.environment["PINPOINT_LLM_RESPONSE"] {
            struct LiveRecap: Decodable { var transcript: String; var response: OpenAIRoundRecap }
            let live = try! JSONDecoder().decode(LiveRecap.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            let liveDrafts = try! HoleRecapLLM.drafts(live.response, transcript: live.transcript, round: round)
            check("real deployed LLM response maps into editable app drafts", liveDrafts.count == 2 && liveDrafts[0].score == 4 && liveDrafts[0].putts == 2 && liveDrafts[0].result.shots[0].contact == .toe)
            check("live carry remains distinct from total distance", liveDrafts[0].result.shots[1].observations.carryYards == 140 && liveDrafts[0].result.shots[1].distanceYards == nil)
            check("real LLM draft saves without parser override", aiStore.applyRecaps(liveDrafts) && aiStore.activeRound?.score(for: 1)?.shots.count == 2 && aiStore.activeRound?.score(for: 1)?.shots[1].carryYards == 140)
        }
        let beforeFailure = store.activeRound
        let activeFile = directory.appendingPathComponent("golf-state.json")
        try? FileManager.default.removeItem(at: activeFile)
        try? FileManager.default.createDirectory(at: activeFile, withIntermediateDirectories: true)
        var edited = batch
        edited[0].score = 7
        check("failed write is reported", !store.applyRecaps(edited))
        check("failed write rolls memory back", store.activeRound == beforeFailure)
        check("shot add failure is reported", !store.addShot(16, TrackedShot(number: 3, club: .iron7)))
        check("shot add failure rolls back", store.activeRound == beforeFailure)
        editedFirst.club = .wood3
        check("shot edit failure is reported", !store.updateShot(16, editedFirst))
        check("shot edit failure rolls back", store.activeRound == beforeFailure)
        check("drag write failure reported", !store.moveShot(1, shot: manual, to: firstPutt))
        check("drag write failure rolls back", store.activeRound == beforeFailure)
        check("score write failure reported", !store.saveScoreEntry(1, score: 8, putts: 2))
        check("score write failure preserves round", store.activeRound == beforeFailure)
        var unsavedSwing = event
        unsavedSwing.id = UUID(); unsavedSwing.roundID = store.activeRound!.id
        check("swing write failure withholds receipt", !store.receiveSwing(unsavedSwing))
        check("swing write failure rolls back", store.activeRound == beforeFailure)
        #endif

        if failed > 0 {
            print("\n\(failed) check(s) failed")
            exit(1)
        }
        print("\nall checks passed")
    }
}
