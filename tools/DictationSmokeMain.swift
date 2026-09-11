import Foundation

@main
struct DictationSmokeMain {
    static func main() {
        var failed = 0
        func check(_ name: String, _ cond: @autoclosure () -> Bool) {
            if cond() {
                print("ok   \(name)")
            } else {
                print("FAIL \(name)")
                failed += 1
            }
        }

        let spoken = "hit a driver off the tee, slightly towed it, so missed left, then hit a four iron, chunked it, hit sand wedge, good contact, put it to about 10 feet left or right, putt, miss the putt on the high side for a par."
        let result = HoleDictationParser.parse(spoken)
        let clubs = result.shots.map { $0.club }
        print("shots: \(result.shots.map { "\($0.club?.displayName ?? "?") lie=\($0.lie?.label ?? "-") contact=\($0.contact?.label ?? "-") shape=\($0.shape?.label ?? "-") note=\($0.note) leftFt=\($0.leftFeet ?? -1)" }.joined(separator: " | "))")
        print("putts=\(result.puttsMentioned ?? -1) score=\(result.scoreCall ?? "-") leftover=\(result.leftoverNote)")

        check("parses four strokes", result.shots.count >= 4)
        check("driver first", clubs.first == .driver)
        check("driver off the tee", result.shots[0].lie == .tee)
        check("toed / towed → toe", result.shots[0].contact == .toe)
        check("missed left → pull", result.shots[0].shape == .pull)
        check("four iron", result.shots.contains { $0.club == .iron4 })
        check("chunked → fat", result.shots.contains { $0.club == .iron4 && $0.contact == .fat })
        check("sand wedge", result.shots.contains { $0.club == .sandWedge })
        check("good contact → pure", result.shots.contains { $0.club == .sandWedge && $0.contact == .pure })
        check("to about 10 feet", result.shots.contains { $0.club == .sandWedge && $0.leftFeet == 10 })
        check("putt is structured", result.shots.contains { $0.club == .putter })
        check("called par", result.scoreCall == "par")
        check("two putts mentioned", result.puttsMentioned == 2)
        check("leftover keeps left or right", result.leftoverNote.contains("left or right"))
        check("leftover keeps high side", result.leftoverNote.contains("high side"))

        guard let hole1 = GeorgetownGPS.layouts[1] else {
            print("FAIL missing hole 1 layout")
            exit(1)
        }
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

        if failed > 0 {
            print("\n\(failed) check(s) failed")
            exit(1)
        }
        print("\nall checks passed")
    }
}
