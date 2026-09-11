import Foundation
#if canImport(MapKit)
import MapKit
#endif

// Real Georgetown Country Club GPS from OpenStreetMap (tees, greens, pins, hole corridors).
// Scorecard yardages / rating match the published Blue tees (18Birdies / club card).

extension GeoPoint {
#if canImport(MapKit)
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
#endif

    /// Offset this point by yards east / north.
    func offset(eastYards: Double, northYards: Double) -> GeoPoint {
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(latitude * .pi / 180)
        let northM = northYards / 1.09361
        let eastM = eastYards / 1.09361
        return GeoPoint(
            latitude: latitude + northM / metersPerDegLat,
            longitude: longitude + eastM / metersPerDegLon
        )
    }

    /// Compass bearing in degrees (0 = north) toward `other`.
    func bearing(to other: GeoPoint) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    func midpoint(to other: GeoPoint) -> GeoPoint {
        GeoPoint(latitude: (latitude + other.latitude) / 2,
                 longitude: (longitude + other.longitude) / 2)
    }

    func interpolated(to other: GeoPoint, t: Double) -> GeoPoint {
        GeoPoint(
            latitude: latitude + (other.latitude - latitude) * t,
            longitude: longitude + (other.longitude - longitude) * t
        )
    }

    /// Planar T along this → `onto` for `from` (0 on this point, 1 on `onto`).
    func projectionT(onto: GeoPoint, from: GeoPoint) -> Double {
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(latitude * .pi / 180)
        let toYds = 1.09361
        let dx = (onto.longitude - longitude) * metersPerDegLon * toYds
        let dy = (onto.latitude - latitude) * metersPerDegLat * toYds
        let px = (from.longitude - longitude) * metersPerDegLon * toYds
        let py = (from.latitude - latitude) * metersPerDegLat * toYds
        let denom = dx * dx + dy * dy
        guard denom > 0 else { return 0 }
        return (px * dx + py * dy) / denom
    }
}

struct HoleLayout: Codable, Hashable, Equatable {
    var tee: GeoPoint
    var pin: GeoPoint
    var greenCenter: GeoPoint
    var greenFront: GeoPoint
    var greenBack: GeoPoint
    var path: [GeoPoint]
    var greenOutline: [GeoPoint]

    func resolvedPin(normalizedX x: Double, normalizedY y: Double) -> GeoPoint {
        greenCenter.offset(eastYards: (x - 0.5) * 24, northYards: (y - 0.5) * 20)
    }

    var headingDegrees: Double { tee.bearing(to: pin) }

    func cameraDistance(extra: Double = 1.0) -> Double {
        let yards = max(160, tee.yards(to: pin) * 1.45)
        return (yards / 1.09361) * 2.15 * extra
    }

    /// Walk the hole corridor a given number of yards from the tee.
    func point(afterTravelling yards: Double, toward pin: GeoPoint) -> GeoPoint {
        let corridor = path.isEmpty ? [tee, pin] : path
        var left = max(0, yards)
        if corridor.count < 2 { return tee }
        for i in 0..<(corridor.count - 1) {
            let a = corridor[i]
            let b = corridor[i + 1]
            let leg = a.yards(to: b)
            if left <= leg || i == corridor.count - 2 {
                let t = leg > 0 ? min(1, left / leg) : 1
                return GeoPoint(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                )
            }
            left -= leg
        }
        return corridor.last ?? pin
    }

    var cameraCenter: GeoPoint {
        tee.midpoint(to: pin)
    }

#if canImport(MapKit)
    func cameraPosition(pin: GeoPoint? = nil) -> MapCameraPosition {
        let target = pin ?? self.pin
        return .camera(
            MapCamera(
                centerCoordinate: cameraCenter.coordinate,
                distance: cameraDistance(),
                heading: tee.bearing(to: target),
                pitch: 0
            )
        )
    }

    func greenCameraPosition(pin: GeoPoint? = nil) -> MapCameraPosition {
        let target = pin ?? greenCenter
        return .camera(
            MapCamera(
                centerCoordinate: target.coordinate,
                distance: 92,
                heading: headingDegrees,
                pitch: 0
            )
        )
    }
#endif

    /// Tee → pin, plus at most one real dogleg apex. OSM jogs become a straight hole.
    var playPath: [GeoPoint] {
        let raw = path.isEmpty ? [tee, pin] : path
        var best: (point: GeoPoint, offset: Double)?
        for point in raw.dropFirst().dropLast() {
            let t = tee.projectionT(onto: pin, from: point)
            guard t > 0.12, t < 0.88 else { continue }
            let proj = tee.interpolated(to: pin, t: min(1, max(0, t)))
            let offset = point.yards(to: proj)
            if offset > 28, best == nil || offset > best!.offset {
                best = (point, offset)
            }
        }
        if let best { return [tee, best.point, pin] }
        return [tee, pin]
    }

    func project(_ point: GeoPoint) -> (along: Double, cross: Double, length: Double) {
        let corridor = playPath
        guard corridor.count >= 2 else {
            return (0, point.yards(to: tee), 0)
        }
        var bestCross = Double.greatestFiniteMagnitude
        var bestAlong = 0.0
        var walked = 0.0
        var length = 0.0
        for i in 0..<(corridor.count - 1) {
            length += corridor[i].yards(to: corridor[i + 1])
        }
        for i in 0..<(corridor.count - 1) {
            let a = corridor[i]
            let b = corridor[i + 1]
            let leg = max(0.001, a.yards(to: b))
            let t = min(1, max(0, a.projectionT(onto: b, from: point)))
            let proj = a.interpolated(to: b, t: t)
            let cross = point.yards(to: proj)
            if cross < bestCross {
                bestCross = cross
                bestAlong = walked + t * leg
            }
            walked += leg
        }
        return (bestAlong, bestCross, length)
    }

    func distanceToCorridor(_ point: GeoPoint) -> Double {
        project(point).cross
    }

    /// True only when the golfer is actually beside this hole — not a neighbor
    /// fairway or someone hundreds of yards away.
    func isStandingOnHole(_ point: GeoPoint) -> Bool {
        let p = project(point)
        return p.cross <= 28 && p.along >= -12 && p.along <= p.length + 18
    }
}

enum GeorgetownGPS {
    static let courseCenter = GeoPoint(latitude: 30.64785, longitude: -97.69810)
    static let address = "1500 Country Club Rd, Georgetown, TX"

    static let layouts: [Int: HoleLayout] = [
        1: HoleLayout(
            tee: GeoPoint(latitude: 30.6507934, longitude: -97.6957171),
            pin: GeoPoint(latitude: 30.6480177, longitude: -97.6966108),
            greenCenter: GeoPoint(latitude: 30.6480323, longitude: -97.6966275),
            greenFront: GeoPoint(latitude: 30.6481173, longitude: -97.6965720),
            greenBack: GeoPoint(latitude: 30.6479159, longitude: -97.6966464),
            path: [
                GeoPoint(latitude: 30.6507934, longitude: -97.6957171),
                GeoPoint(latitude: 30.6490197, longitude: -97.6962072),
                GeoPoint(latitude: 30.6480177, longitude: -97.6966108)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6481179, longitude: -97.6966096),
                GeoPoint(latitude: 30.6481098, longitude: -97.6966401),
                GeoPoint(latitude: 30.6480884, longitude: -97.6966833),
                GeoPoint(latitude: 30.6480535, longitude: -97.6967172),
                GeoPoint(latitude: 30.6480267, longitude: -97.6967246),
                GeoPoint(latitude: 30.6479979, longitude: -97.6967212),
                GeoPoint(latitude: 30.6479555, longitude: -97.6966984),
                GeoPoint(latitude: 30.6479229, longitude: -97.6966632),
                GeoPoint(latitude: 30.6479159, longitude: -97.6966096),
                GeoPoint(latitude: 30.6479324, longitude: -97.6965784),
                GeoPoint(latitude: 30.6479852, longitude: -97.6965465),
                GeoPoint(latitude: 30.6480682, longitude: -97.6965365),
                GeoPoint(latitude: 30.6480933, longitude: -97.6965435),
                GeoPoint(latitude: 30.6481118, longitude: -97.6965599),
                GeoPoint(latitude: 30.6481190, longitude: -97.6965868),
                GeoPoint(latitude: 30.6481179, longitude: -97.6966096)
            ]
        ),
        2: HoleLayout(
            tee: GeoPoint(latitude: 30.6474266, longitude: -97.6966324),
            pin: GeoPoint(latitude: 30.6459714, longitude: -97.6995994),
            greenCenter: GeoPoint(latitude: 30.6459660, longitude: -97.6995785),
            greenFront: GeoPoint(latitude: 30.6460187, longitude: -97.6994915),
            greenBack: GeoPoint(latitude: 30.6458984, longitude: -97.6996535),
            path: [
                GeoPoint(latitude: 30.6474266, longitude: -97.6966324),
                GeoPoint(latitude: 30.6465572, longitude: -97.6988692),
                GeoPoint(latitude: 30.6459714, longitude: -97.6995994)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6458883, longitude: -97.6996448),
                GeoPoint(latitude: 30.6459085, longitude: -97.6996582),
                GeoPoint(latitude: 30.6459826, longitude: -97.6996639),
                GeoPoint(latitude: 30.6460247, longitude: -97.6996488),
                GeoPoint(latitude: 30.6460501, longitude: -97.6995998),
                GeoPoint(latitude: 30.6460510, longitude: -97.6995563),
                GeoPoint(latitude: 30.6460308, longitude: -97.6995026),
                GeoPoint(latitude: 30.6460187, longitude: -97.6994915),
                GeoPoint(latitude: 30.6459976, longitude: -97.6994909),
                GeoPoint(latitude: 30.6459878, longitude: -97.6995003),
                GeoPoint(latitude: 30.6459624, longitude: -97.6995331),
                GeoPoint(latitude: 30.6459421, longitude: -97.6995562),
                GeoPoint(latitude: 30.6459007, longitude: -97.6995824),
                GeoPoint(latitude: 30.6458814, longitude: -97.6996012),
                GeoPoint(latitude: 30.6458805, longitude: -97.6996310),
                GeoPoint(latitude: 30.6458883, longitude: -97.6996448)
            ]
        ),
        3: HoleLayout(
            tee: GeoPoint(latitude: 30.6455953, longitude: -97.6997331),
            pin: GeoPoint(latitude: 30.6448846, longitude: -97.7005422),
            greenCenter: GeoPoint(latitude: 30.6448968, longitude: -97.7005463),
            greenFront: GeoPoint(latitude: 30.6449599, longitude: -97.7004736),
            greenBack: GeoPoint(latitude: 30.6448402, longitude: -97.7006329),
            path: [
                GeoPoint(latitude: 30.6455953, longitude: -97.6997331),
                GeoPoint(latitude: 30.6448846, longitude: -97.7005422)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6449639, longitude: -97.7005712),
                GeoPoint(latitude: 30.6449319, longitude: -97.7006104),
                GeoPoint(latitude: 30.6448944, longitude: -97.7006396),
                GeoPoint(latitude: 30.6448497, longitude: -97.7006393),
                GeoPoint(latitude: 30.6448315, longitude: -97.7006248),
                GeoPoint(latitude: 30.6448203, longitude: -97.7006027),
                GeoPoint(latitude: 30.6448185, longitude: -97.7005732),
                GeoPoint(latitude: 30.6448260, longitude: -97.7005450),
                GeoPoint(latitude: 30.6448627, longitude: -97.7004746),
                GeoPoint(latitude: 30.6448791, longitude: -97.7004552),
                GeoPoint(latitude: 30.6449013, longitude: -97.7004461),
                GeoPoint(latitude: 30.6449273, longitude: -97.7004505),
                GeoPoint(latitude: 30.6449599, longitude: -97.7004736),
                GeoPoint(latitude: 30.6449792, longitude: -97.7005222),
                GeoPoint(latitude: 30.6449749, longitude: -97.7005467),
                GeoPoint(latitude: 30.6449639, longitude: -97.7005712)
            ]
        ),
        4: HoleLayout(
            tee: GeoPoint(latitude: 30.6455692, longitude: -97.6997800),
            pin: GeoPoint(latitude: 30.6421251, longitude: -97.7027390),
            greenCenter: GeoPoint(latitude: 30.6422308, longitude: -97.7026782),
            greenFront: GeoPoint(latitude: 30.6424171, longitude: -97.7025464),
            greenBack: GeoPoint(latitude: 30.6420479, longitude: -97.7028061),
            path: [
                GeoPoint(latitude: 30.6455692, longitude: -97.6997800),
                GeoPoint(latitude: 30.6454519, longitude: -97.7003851),
                GeoPoint(latitude: 30.6443200, longitude: -97.7022861),
                GeoPoint(latitude: 30.6434002, longitude: -97.7029085),
                GeoPoint(latitude: 30.6421251, longitude: -97.7027390)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6421680, longitude: -97.7027968),
                GeoPoint(latitude: 30.6422353, longitude: -97.7027157),
                GeoPoint(latitude: 30.6422744, longitude: -97.7026806),
                GeoPoint(latitude: 30.6423282, longitude: -97.7026719),
                GeoPoint(latitude: 30.6424065, longitude: -97.7026310),
                GeoPoint(latitude: 30.6424281, longitude: -97.7025960),
                GeoPoint(latitude: 30.6424055, longitude: -97.7025312),
                GeoPoint(latitude: 30.6423679, longitude: -97.7025195),
                GeoPoint(latitude: 30.6422679, longitude: -97.7025791),
                GeoPoint(latitude: 30.6421785, longitude: -97.7026258),
                GeoPoint(latitude: 30.6420951, longitude: -97.7026725),
                GeoPoint(latitude: 30.6420479, longitude: -97.7027326),
                GeoPoint(latitude: 30.6420424, longitude: -97.7027968),
                GeoPoint(latitude: 30.6420695, longitude: -97.7028237),
                GeoPoint(latitude: 30.6421137, longitude: -97.7028242),
                GeoPoint(latitude: 30.6421680, longitude: -97.7027968)
            ]
        ),
        5: HoleLayout(
            tee: GeoPoint(latitude: 30.6417679, longitude: -97.7028837),
            pin: GeoPoint(latitude: 30.6437084, longitude: -97.7036429),
            greenCenter: GeoPoint(latitude: 30.6437001, longitude: -97.7036487),
            greenFront: GeoPoint(latitude: 30.6436256, longitude: -97.7036111),
            greenBack: GeoPoint(latitude: 30.6437721, longitude: -97.7036614),
            path: [
                GeoPoint(latitude: 30.6417679, longitude: -97.7028837),
                GeoPoint(latitude: 30.6431847, longitude: -97.7039154),
                GeoPoint(latitude: 30.6437084, longitude: -97.7036429)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6437437, longitude: -97.7036935),
                GeoPoint(latitude: 30.6436903, longitude: -97.7037453),
                GeoPoint(latitude: 30.6436685, longitude: -97.7037560),
                GeoPoint(latitude: 30.6436492, longitude: -97.7037514),
                GeoPoint(latitude: 30.6436248, longitude: -97.7037260),
                GeoPoint(latitude: 30.6436138, longitude: -97.7036802),
                GeoPoint(latitude: 30.6436178, longitude: -97.7036360),
                GeoPoint(latitude: 30.6436387, longitude: -97.7035827),
                GeoPoint(latitude: 30.6436763, longitude: -97.7035430),
                GeoPoint(latitude: 30.6437118, longitude: -97.7035334),
                GeoPoint(latitude: 30.6437480, longitude: -97.7035461),
                GeoPoint(latitude: 30.6437747, longitude: -97.7035766),
                GeoPoint(latitude: 30.6437813, longitude: -97.7036177),
                GeoPoint(latitude: 30.6437769, longitude: -97.7036477),
                GeoPoint(latitude: 30.6437655, longitude: -97.7036701),
                GeoPoint(latitude: 30.6437437, longitude: -97.7036935)
            ]
        ),
        6: HoleLayout(
            tee: GeoPoint(latitude: 30.6435372, longitude: -97.7043618),
            pin: GeoPoint(latitude: 30.6457127, longitude: -97.7002494),
            greenCenter: GeoPoint(latitude: 30.6457012, longitude: -97.7002760),
            greenFront: GeoPoint(latitude: 30.6456608, longitude: -97.7003679),
            greenBack: GeoPoint(latitude: 30.6457420, longitude: -97.7001996),
            path: [
                GeoPoint(latitude: 30.6435372, longitude: -97.7043618),
                GeoPoint(latitude: 30.6448144, longitude: -97.7025782),
                GeoPoint(latitude: 30.6456853, longitude: -97.7012156),
                GeoPoint(latitude: 30.6457127, longitude: -97.7002494)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6457248, longitude: -97.7003340),
                GeoPoint(latitude: 30.6457662, longitude: -97.7002751),
                GeoPoint(latitude: 30.6457771, longitude: -97.7002520),
                GeoPoint(latitude: 30.6457751, longitude: -97.7002320),
                GeoPoint(latitude: 30.6457599, longitude: -97.7002116),
                GeoPoint(latitude: 30.6457208, longitude: -97.7001908),
                GeoPoint(latitude: 30.6456936, longitude: -97.7001850),
                GeoPoint(latitude: 30.6456767, longitude: -97.7001908),
                GeoPoint(latitude: 30.6456549, longitude: -97.7002266),
                GeoPoint(latitude: 30.6456479, longitude: -97.7002736),
                GeoPoint(latitude: 30.6456370, longitude: -97.7003286),
                GeoPoint(latitude: 30.6456419, longitude: -97.7003502),
                GeoPoint(latitude: 30.6456608, longitude: -97.7003679),
                GeoPoint(latitude: 30.6456847, longitude: -97.7003683),
                GeoPoint(latitude: 30.6457082, longitude: -97.7003566),
                GeoPoint(latitude: 30.6457248, longitude: -97.7003340)
            ]
        ),
        7: HoleLayout(
            tee: GeoPoint(latitude: 30.6458530, longitude: -97.6999523),
            pin: GeoPoint(latitude: 30.6469099, longitude: -97.6996036),
            greenCenter: GeoPoint(latitude: 30.6469070, longitude: -97.6996202),
            greenFront: GeoPoint(latitude: 30.6468436, longitude: -97.6996917),
            greenBack: GeoPoint(latitude: 30.6469769, longitude: -97.6995468),
            path: [
                GeoPoint(latitude: 30.6458530, longitude: -97.6999523),
                GeoPoint(latitude: 30.6469099, longitude: -97.6996036)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6469371, longitude: -97.6997121),
                GeoPoint(latitude: 30.6469636, longitude: -97.6996719),
                GeoPoint(latitude: 30.6469821, longitude: -97.6996065),
                GeoPoint(latitude: 30.6469812, longitude: -97.6995619),
                GeoPoint(latitude: 30.6469590, longitude: -97.6995217),
                GeoPoint(latitude: 30.6469399, longitude: -97.6995106),
                GeoPoint(latitude: 30.6469062, longitude: -97.6995073),
                GeoPoint(latitude: 30.6468719, longitude: -97.6995153),
                GeoPoint(latitude: 30.6468551, longitude: -97.6995371),
                GeoPoint(latitude: 30.6468396, longitude: -97.6995884),
                GeoPoint(latitude: 30.6468361, longitude: -97.6996461),
                GeoPoint(latitude: 30.6468436, longitude: -97.6996917),
                GeoPoint(latitude: 30.6468664, longitude: -97.6997312),
                GeoPoint(latitude: 30.6468834, longitude: -97.6997369),
                GeoPoint(latitude: 30.6469212, longitude: -97.6997299),
                GeoPoint(latitude: 30.6469371, longitude: -97.6997121)
            ]
        ),
        8: HoleLayout(
            tee: GeoPoint(latitude: 30.6470207, longitude: -97.6993166),
            pin: GeoPoint(latitude: 30.6476945, longitude: -97.6967364),
            greenCenter: GeoPoint(latitude: 30.6476839, longitude: -97.6967946),
            greenFront: GeoPoint(latitude: 30.6476345, longitude: -97.6968822),
            greenBack: GeoPoint(latitude: 30.6477180, longitude: -97.6966904),
            path: [
                GeoPoint(latitude: 30.6470207, longitude: -97.6993166),
                GeoPoint(latitude: 30.6475399, longitude: -97.6975437),
                GeoPoint(latitude: 30.6476945, longitude: -97.6967364)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6476696, longitude: -97.6968741),
                GeoPoint(latitude: 30.6477193, longitude: -97.6968545),
                GeoPoint(latitude: 30.6477674, longitude: -97.6968421),
                GeoPoint(latitude: 30.6477796, longitude: -97.6968202),
                GeoPoint(latitude: 30.6477789, longitude: -97.6967824),
                GeoPoint(latitude: 30.6477617, longitude: -97.6967372),
                GeoPoint(latitude: 30.6477299, longitude: -97.6966954),
                GeoPoint(latitude: 30.6477051, longitude: -97.6966889),
                GeoPoint(latitude: 30.6476534, longitude: -97.6967008),
                GeoPoint(latitude: 30.6476289, longitude: -97.6967201),
                GeoPoint(latitude: 30.6476040, longitude: -97.6967643),
                GeoPoint(latitude: 30.6476000, longitude: -97.6968009),
                GeoPoint(latitude: 30.6476037, longitude: -97.6968441),
                GeoPoint(latitude: 30.6476166, longitude: -97.6968672),
                GeoPoint(latitude: 30.6476431, longitude: -97.6968830),
                GeoPoint(latitude: 30.6476696, longitude: -97.6968741)
            ]
        ),
        9: HoleLayout(
            tee: GeoPoint(latitude: 30.6479599, longitude: -97.6969858),
            pin: GeoPoint(latitude: 30.6501243, longitude: -97.6967337),
            greenCenter: GeoPoint(latitude: 30.6501205, longitude: -97.6967805),
            greenFront: GeoPoint(latitude: 30.6500164, longitude: -97.6968119),
            greenBack: GeoPoint(latitude: 30.6501897, longitude: -97.6967303),
            path: [
                GeoPoint(latitude: 30.6479599, longitude: -97.6969858),
                GeoPoint(latitude: 30.6495567, longitude: -97.6968544),
                GeoPoint(latitude: 30.6501243, longitude: -97.6967337)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6501887, longitude: -97.6967434),
                GeoPoint(latitude: 30.6501798, longitude: -97.6967931),
                GeoPoint(latitude: 30.6501715, longitude: -97.6968555),
                GeoPoint(latitude: 30.6501626, longitude: -97.6968859),
                GeoPoint(latitude: 30.6501433, longitude: -97.6969025),
                GeoPoint(latitude: 30.6501069, longitude: -97.6969067),
                GeoPoint(latitude: 30.6500671, longitude: -97.6968890),
                GeoPoint(latitude: 30.6500284, longitude: -97.6968478),
                GeoPoint(latitude: 30.6500158, longitude: -97.6967823),
                GeoPoint(latitude: 30.6500313, longitude: -97.6967291),
                GeoPoint(latitude: 30.6500711, longitude: -97.6966775),
                GeoPoint(latitude: 30.6501142, longitude: -97.6966529),
                GeoPoint(latitude: 30.6501433, longitude: -97.6966567),
                GeoPoint(latitude: 30.6501669, longitude: -97.6966771),
                GeoPoint(latitude: 30.6501874, longitude: -97.6967176),
                GeoPoint(latitude: 30.6501887, longitude: -97.6967434)
            ]
        ),
        10: HoleLayout(
            tee: GeoPoint(latitude: 30.6514957, longitude: -97.6955480),
            pin: GeoPoint(latitude: 30.6527572, longitude: -97.6967996),
            greenCenter: GeoPoint(latitude: 30.6527407, longitude: -97.6967840),
            greenFront: GeoPoint(latitude: 30.6526804, longitude: -97.6967040),
            greenBack: GeoPoint(latitude: 30.6528098, longitude: -97.6968774),
            path: [
                GeoPoint(latitude: 30.6514957, longitude: -97.6955480),
                GeoPoint(latitude: 30.6527572, longitude: -97.6967996)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6526629, longitude: -97.6967650),
                GeoPoint(latitude: 30.6526800, longitude: -97.6968336),
                GeoPoint(latitude: 30.6526956, longitude: -97.6968677),
                GeoPoint(latitude: 30.6527215, longitude: -97.6968885),
                GeoPoint(latitude: 30.6527657, longitude: -97.6968969),
                GeoPoint(latitude: 30.6527988, longitude: -97.6968863),
                GeoPoint(latitude: 30.6528205, longitude: -97.6968579),
                GeoPoint(latitude: 30.6528327, longitude: -97.6968128),
                GeoPoint(latitude: 30.6528197, longitude: -97.6967394),
                GeoPoint(latitude: 30.6527961, longitude: -97.6967049),
                GeoPoint(latitude: 30.6527683, longitude: -97.6966916),
                GeoPoint(latitude: 30.6527185, longitude: -97.6966889),
                GeoPoint(latitude: 30.6526903, longitude: -97.6966982),
                GeoPoint(latitude: 30.6526724, longitude: -97.6967124),
                GeoPoint(latitude: 30.6526637, longitude: -97.6967363),
                GeoPoint(latitude: 30.6526629, longitude: -97.6967650)
            ]
        ),
        11: HoleLayout(
            tee: GeoPoint(latitude: 30.6531328, longitude: -97.6967062),
            pin: GeoPoint(latitude: 30.6511864, longitude: -97.6938388),
            greenCenter: GeoPoint(latitude: 30.6512019, longitude: -97.6938543),
            greenFront: GeoPoint(latitude: 30.6512638, longitude: -97.6939517),
            greenBack: GeoPoint(latitude: 30.6511528, longitude: -97.6937460),
            path: [
                GeoPoint(latitude: 30.6531328, longitude: -97.6967062),
                GeoPoint(latitude: 30.6518352, longitude: -97.6953145),
                GeoPoint(latitude: 30.6511864, longitude: -97.6938388)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6512387, longitude: -97.6937657),
                GeoPoint(latitude: 30.6512701, longitude: -97.6938292),
                GeoPoint(latitude: 30.6512824, longitude: -97.6938932),
                GeoPoint(latitude: 30.6512797, longitude: -97.6939282),
                GeoPoint(latitude: 30.6512638, longitude: -97.6939517),
                GeoPoint(latitude: 30.6512393, longitude: -97.6939675),
                GeoPoint(latitude: 30.6512092, longitude: -97.6939679),
                GeoPoint(latitude: 30.6511575, longitude: -97.6939425),
                GeoPoint(latitude: 30.6511340, longitude: -97.6939151),
                GeoPoint(latitude: 30.6511240, longitude: -97.6938735),
                GeoPoint(latitude: 30.6511257, longitude: -97.6938269),
                GeoPoint(latitude: 30.6511343, longitude: -97.6937738),
                GeoPoint(latitude: 30.6511528, longitude: -97.6937460),
                GeoPoint(latitude: 30.6511837, longitude: -97.6937360),
                GeoPoint(latitude: 30.6512138, longitude: -97.6937449),
                GeoPoint(latitude: 30.6512387, longitude: -97.6937657)
            ]
        ),
        12: HoleLayout(
            tee: GeoPoint(latitude: 30.6511843, longitude: -97.6932644),
            pin: GeoPoint(latitude: 30.6496109, longitude: -97.6946298),
            greenCenter: GeoPoint(latitude: 30.6496076, longitude: -97.6946273),
            greenFront: GeoPoint(latitude: 30.6496829, longitude: -97.6945534),
            greenBack: GeoPoint(latitude: 30.6495453, longitude: -97.6946941),
            path: [
                GeoPoint(latitude: 30.6511843, longitude: -97.6932644),
                GeoPoint(latitude: 30.6503314, longitude: -97.6943208),
                GeoPoint(latitude: 30.6496109, longitude: -97.6946298)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6495684, longitude: -97.6947087),
                GeoPoint(latitude: 30.6496131, longitude: -97.6947221),
                GeoPoint(latitude: 30.6496498, longitude: -97.6947140),
                GeoPoint(latitude: 30.6496784, longitude: -97.6946883),
                GeoPoint(latitude: 30.6497000, longitude: -97.6946509),
                GeoPoint(latitude: 30.6497055, longitude: -97.6946118),
                GeoPoint(latitude: 30.6496970, longitude: -97.6945739),
                GeoPoint(latitude: 30.6496573, longitude: -97.6945324),
                GeoPoint(latitude: 30.6496076, longitude: -97.6945184),
                GeoPoint(latitude: 30.6495850, longitude: -97.6945190),
                GeoPoint(latitude: 30.6495523, longitude: -97.6945488),
                GeoPoint(latitude: 30.6495267, longitude: -97.6945896),
                GeoPoint(latitude: 30.6495197, longitude: -97.6946328),
                GeoPoint(latitude: 30.6495242, longitude: -97.6946644),
                GeoPoint(latitude: 30.6495453, longitude: -97.6946941),
                GeoPoint(latitude: 30.6495684, longitude: -97.6947087)
            ]
        ),
        13: HoleLayout(
            tee: GeoPoint(latitude: 30.6493653, longitude: -97.6947977),
            pin: GeoPoint(latitude: 30.6466688, longitude: -97.6960511),
            greenCenter: GeoPoint(latitude: 30.6466669, longitude: -97.6960659),
            greenFront: GeoPoint(latitude: 30.6467263, longitude: -97.6959803),
            greenBack: GeoPoint(latitude: 30.6465695, longitude: -97.6961363),
            path: [
                GeoPoint(latitude: 30.6493653, longitude: -97.6947977),
                GeoPoint(latitude: 30.6477321, longitude: -97.6957990),
                GeoPoint(latitude: 30.6466688, longitude: -97.6960511)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6467379, longitude: -97.6960185),
                GeoPoint(latitude: 30.6467432, longitude: -97.6960704),
                GeoPoint(latitude: 30.6467379, longitude: -97.6961170),
                GeoPoint(latitude: 30.6467044, longitude: -97.6961625),
                GeoPoint(latitude: 30.6466749, longitude: -97.6961767),
                GeoPoint(latitude: 30.6466421, longitude: -97.6961775),
                GeoPoint(latitude: 30.6465944, longitude: -97.6961633),
                GeoPoint(latitude: 30.6465695, longitude: -97.6961363),
                GeoPoint(latitude: 30.6465632, longitude: -97.6960982),
                GeoPoint(latitude: 30.6465801, longitude: -97.6960527),
                GeoPoint(latitude: 30.6466332, longitude: -97.6959699),
                GeoPoint(latitude: 30.6466560, longitude: -97.6959511),
                GeoPoint(latitude: 30.6466815, longitude: -97.6959480),
                GeoPoint(latitude: 30.6467200, longitude: -97.6959711),
                GeoPoint(latitude: 30.6467316, longitude: -97.6959961),
                GeoPoint(latitude: 30.6467379, longitude: -97.6960185)
            ]
        ),
        14: HoleLayout(
            tee: GeoPoint(latitude: 30.6468777, longitude: -97.6954786),
            pin: GeoPoint(latitude: 30.6456904, longitude: -97.6959621),
            greenCenter: GeoPoint(latitude: 30.6457054, longitude: -97.6959817),
            greenFront: GeoPoint(latitude: 30.6457692, longitude: -97.6959055),
            greenBack: GeoPoint(latitude: 30.6456370, longitude: -97.6960488),
            path: [
                GeoPoint(latitude: 30.6468777, longitude: -97.6954786),
                GeoPoint(latitude: 30.6456904, longitude: -97.6959621)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6457523, longitude: -97.6960137),
                GeoPoint(latitude: 30.6457298, longitude: -97.6960542),
                GeoPoint(latitude: 30.6457125, longitude: -97.6960800),
                GeoPoint(latitude: 30.6456804, longitude: -97.6960865),
                GeoPoint(latitude: 30.6456565, longitude: -97.6960769),
                GeoPoint(latitude: 30.6456413, longitude: -97.6960592),
                GeoPoint(latitude: 30.6456330, longitude: -97.6960307),
                GeoPoint(latitude: 30.6456347, longitude: -97.6959513),
                GeoPoint(latitude: 30.6456555, longitude: -97.6958886),
                GeoPoint(latitude: 30.6456830, longitude: -97.6958751),
                GeoPoint(latitude: 30.6457225, longitude: -97.6958720),
                GeoPoint(latitude: 30.6457523, longitude: -97.6958797),
                GeoPoint(latitude: 30.6457692, longitude: -97.6959055),
                GeoPoint(latitude: 30.6457722, longitude: -97.6959583),
                GeoPoint(latitude: 30.6457646, longitude: -97.6959895),
                GeoPoint(latitude: 30.6457523, longitude: -97.6960137)
            ]
        ),
        15: HoleLayout(
            tee: GeoPoint(latitude: 30.6467181, longitude: -97.6955262),
            pin: GeoPoint(latitude: 30.6452902, longitude: -97.6995377),
            greenCenter: GeoPoint(latitude: 30.6452956, longitude: -97.6995457),
            greenFront: GeoPoint(latitude: 30.6453248, longitude: -97.6994274),
            greenBack: GeoPoint(latitude: 30.6452430, longitude: -97.6996558),
            path: [
                GeoPoint(latitude: 30.6467181, longitude: -97.6955262),
                GeoPoint(latitude: 30.6457070, longitude: -97.6966147),
                GeoPoint(latitude: 30.6457274, longitude: -97.6981799),
                GeoPoint(latitude: 30.6455910, longitude: -97.6990092),
                GeoPoint(latitude: 30.6452902, longitude: -97.6995377)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6452997, longitude: -97.6996377),
                GeoPoint(latitude: 30.6453199, longitude: -97.6996088),
                GeoPoint(latitude: 30.6453610, longitude: -97.6995656),
                GeoPoint(latitude: 30.6453739, longitude: -97.6995448),
                GeoPoint(latitude: 30.6453765, longitude: -97.6994948),
                GeoPoint(latitude: 30.6453673, longitude: -97.6994539),
                GeoPoint(latitude: 30.6453351, longitude: -97.6994297),
                GeoPoint(latitude: 30.6453172, longitude: -97.6994274),
                GeoPoint(latitude: 30.6452649, longitude: -97.6994493),
                GeoPoint(latitude: 30.6452404, longitude: -97.6994747),
                GeoPoint(latitude: 30.6452165, longitude: -97.6995394),
                GeoPoint(latitude: 30.6452145, longitude: -97.6995972),
                GeoPoint(latitude: 30.6452238, longitude: -97.6996427),
                GeoPoint(latitude: 30.6452430, longitude: -97.6996558),
                GeoPoint(latitude: 30.6452795, longitude: -97.6996534),
                GeoPoint(latitude: 30.6452997, longitude: -97.6996377)
            ]
        ),
        16: HoleLayout(
            tee: GeoPoint(latitude: 30.6459597, longitude: -97.6991628),
            pin: GeoPoint(latitude: 30.6470826, longitude: -97.6962724),
            greenCenter: GeoPoint(latitude: 30.6470723, longitude: -97.6962880),
            greenFront: GeoPoint(latitude: 30.6470259, longitude: -97.6963885),
            greenBack: GeoPoint(latitude: 30.6471349, longitude: -97.6961994),
            path: [
                GeoPoint(latitude: 30.6459597, longitude: -97.6991628),
                GeoPoint(latitude: 30.6466728, longitude: -97.6968952),
                GeoPoint(latitude: 30.6470826, longitude: -97.6962724)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6470613, longitude: -97.6963931),
                GeoPoint(latitude: 30.6470895, longitude: -97.6963835),
                GeoPoint(latitude: 30.6471425, longitude: -97.6963111),
                GeoPoint(latitude: 30.6471544, longitude: -97.6962780),
                GeoPoint(latitude: 30.6471554, longitude: -97.6962229),
                GeoPoint(latitude: 30.6471452, longitude: -97.6962052),
                GeoPoint(latitude: 30.6471216, longitude: -97.6961971),
                GeoPoint(latitude: 30.6470882, longitude: -97.6961979),
                GeoPoint(latitude: 30.6470716, longitude: -97.6962056),
                GeoPoint(latitude: 30.6470418, longitude: -97.6962456),
                GeoPoint(latitude: 30.6470196, longitude: -97.6962676),
                GeoPoint(latitude: 30.6469977, longitude: -97.6962903),
                GeoPoint(latitude: 30.6469871, longitude: -97.6963304),
                GeoPoint(latitude: 30.6469918, longitude: -97.6963596),
                GeoPoint(latitude: 30.6470259, longitude: -97.6963885),
                GeoPoint(latitude: 30.6470613, longitude: -97.6963931)
            ]
        ),
        17: HoleLayout(
            tee: GeoPoint(latitude: 30.6476260, longitude: -97.6964357),
            pin: GeoPoint(latitude: 30.6486889, longitude: -97.6958842),
            greenCenter: GeoPoint(latitude: 30.6486440, longitude: -97.6959001),
            greenFront: GeoPoint(latitude: 30.6485684, longitude: -97.6959510),
            greenBack: GeoPoint(latitude: 30.6487370, longitude: -97.6958461),
            path: [
                GeoPoint(latitude: 30.6476260, longitude: -97.6964357),
                GeoPoint(latitude: 30.6486889, longitude: -97.6958842)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6485608, longitude: -97.6959032),
                GeoPoint(latitude: 30.6485627, longitude: -97.6959373),
                GeoPoint(latitude: 30.6485741, longitude: -97.6959612),
                GeoPoint(latitude: 30.6485939, longitude: -97.6959771),
                GeoPoint(latitude: 30.6486244, longitude: -97.6959789),
                GeoPoint(latitude: 30.6486776, longitude: -97.6959625),
                GeoPoint(latitude: 30.6487130, longitude: -97.6959377),
                GeoPoint(latitude: 30.6487347, longitude: -97.6958970),
                GeoPoint(latitude: 30.6487397, longitude: -97.6958630),
                GeoPoint(latitude: 30.6487321, longitude: -97.6958369),
                GeoPoint(latitude: 30.6487165, longitude: -97.6958284),
                GeoPoint(latitude: 30.6486894, longitude: -97.6958284),
                GeoPoint(latitude: 30.6486255, longitude: -97.6958466),
                GeoPoint(latitude: 30.6485863, longitude: -97.6958612),
                GeoPoint(latitude: 30.6485696, longitude: -97.6958789),
                GeoPoint(latitude: 30.6485608, longitude: -97.6959032)
            ]
        ),
        18: HoleLayout(
            tee: GeoPoint(latitude: 30.6483839, longitude: -97.6955294),
            pin: GeoPoint(latitude: 30.6510884, longitude: -97.6950379),
            greenCenter: GeoPoint(latitude: 30.6511088, longitude: -97.6950569),
            greenFront: GeoPoint(latitude: 30.6510080, longitude: -97.6950939),
            greenBack: GeoPoint(latitude: 30.6512226, longitude: -97.6950106),
            path: [
                GeoPoint(latitude: 30.6483839, longitude: -97.6955294),
                GeoPoint(latitude: 30.6487691, longitude: -97.6954664),
                GeoPoint(latitude: 30.6502346, longitude: -97.6954295),
                GeoPoint(latitude: 30.6510884, longitude: -97.6950379)
            ],
            greenOutline: [
                GeoPoint(latitude: 30.6511234, longitude: -97.6951447),
                GeoPoint(latitude: 30.6511741, longitude: -97.6951249),
                GeoPoint(latitude: 30.6512135, longitude: -97.6950685),
                GeoPoint(latitude: 30.6512244, longitude: -97.6950273),
                GeoPoint(latitude: 30.6512187, longitude: -97.6949999),
                GeoPoint(latitude: 30.6512016, longitude: -97.6949801),
                GeoPoint(latitude: 30.6511295, longitude: -97.6949628),
                GeoPoint(latitude: 30.6510792, longitude: -97.6949597),
                GeoPoint(latitude: 30.6510486, longitude: -97.6949674),
                GeoPoint(latitude: 30.6510237, longitude: -97.6949872),
                GeoPoint(latitude: 30.6510084, longitude: -97.6950482),
                GeoPoint(latitude: 30.6510080, longitude: -97.6950939),
                GeoPoint(latitude: 30.6510224, longitude: -97.6951305),
                GeoPoint(latitude: 30.6510429, longitude: -97.6951478),
                GeoPoint(latitude: 30.6510849, longitude: -97.6951574),
                GeoPoint(latitude: 30.6511234, longitude: -97.6951447)
            ]
        ),
    ]

    static func layout(for holeNumber: Int) -> HoleLayout? {
        layouts[holeNumber]
    }

    /// The hole whose fairway the point is actually on, if any.
    static func standingHole(at point: GeoPoint) -> Int? {
        var best: (number: Int, cross: Double)?
        for (number, layout) in layouts where layout.isStandingOnHole(point) {
            let cross = layout.distanceToCorridor(point)
            if best == nil || cross < best!.cross {
                best = (number, cross)
            }
        }
        return best?.number
    }

    static func isStanding(on holeNumber: Int, at point: GeoPoint) -> Bool {
        guard let layout = layouts[holeNumber], layout.isStandingOnHole(point) else { return false }
        let thisCross = layout.distanceToCorridor(point)
        // Shared tees are a few yards apart — keep GPS on the hole being played.
        // Only ignore this hole when another corridor is clearly closer.
        for (number, other) in layouts where number != holeNumber && other.isStandingOnHole(point) {
            if other.distanceToCorridor(point) + 14 < thisCross {
                return false
            }
        }
        return true
    }
}
