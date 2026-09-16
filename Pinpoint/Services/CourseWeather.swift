import Foundation

/// NWS station observations for US courses. Requests use course coordinates,
/// not the golfer's live GPS. Actor coalesces concurrent map refreshes.
actor CourseWeather {
    static let shared = CourseWeather()
    private var tasks: [String: Task<CourseWind, Error>] = [:]
    private var cached: [String: (Date, CourseWind)] = [:]
    private var attempts: [String: Date] = [:]
    enum Failure: Error { case unavailable }
    struct PointResponse: Decodable {
        struct Properties: Decodable { var observationStations: URL }
        var properties: Properties
    }
    struct Stations: Decodable {
        struct Station: Decodable {
            struct Properties: Decodable { var stationIdentifier: String; var name: String }
            var properties: Properties
        }
        var features: [Station]
    }
    struct Observation: Decodable {
        struct Quantity: Decodable { var value: Double?; var unitCode: String }
        struct Properties: Decodable {
            var timestamp: String
            var windSpeed: Quantity
            var windDirection: Quantity
        }
        var properties: Properties
        func wind(station: String, id: String, now: Date = Date()) throws -> CourseWind {
            guard let mph = CourseWind.milesPerHour(value: properties.windSpeed.value, unit: properties.windSpeed.unitCode),
                  let date = ISO8601DateFormatter().date(from: properties.timestamp) else { throw Failure.unavailable }
            let direction = properties.windDirection.value.flatMap { value -> Double? in
                guard value.isFinite, (0...360).contains(value), properties.windDirection.unitCode == "wmoUnit:degree_(angle)" else { return nil }
                return value.truncatingRemainder(dividingBy: 360)
            }
            let result = CourseWind(mph: mph, fromDegrees: direction, observedAt: date, station: station, stationID: id)
            guard result.isFresh(at: now) else { throw Failure.unavailable }
            return result
        }
    }
    private static func get<T: Decodable>(_ url: URL) async throws -> T {
        guard url.scheme == "https", url.host == "api.weather.gov" else { throw Failure.unavailable }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Pinpoint/1.0 (com.pinpointreplay.mobile)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.unavailable }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func wind(at point: GeoPoint) async throws -> CourseWind {
        let key = String(format: "%.4f,%.4f", locale: Locale(identifier: "en_US_POSIX"), point.latitude, point.longitude)
        if let (fetched, wind) = cached[key], Date().timeIntervalSince(fetched) < 600, wind.isFresh() { return wind }
        if let task = tasks[key] { return try await task.value }
        if let attempted = attempts[key], Date().timeIntervalSince(attempted) < 60 { throw Failure.unavailable }
        attempts[key] = Date()
        let task = Task<CourseWind, Error> {
            let pointResponse: PointResponse = try await Self.get(URL(string: "https://api.weather.gov/points/\(key)")!)
            let stations: Stations = try await Self.get(pointResponse.properties.observationStations)
            for station in stations.features.prefix(3) {
                let id = station.properties.stationIdentifier
                guard id.allSatisfy({ $0.isLetter || $0.isNumber }) else { continue }
                do {
                    let observation: Observation = try await Self.get(URL(string: "https://api.weather.gov/stations/\(id)/observations/latest")!)
                    return try observation.wind(station: station.properties.name, id: id)
                } catch { continue }
            }
            throw Failure.unavailable
        }
        tasks[key] = task
        defer { tasks[key] = nil }
        let result = try await task.value
        cached[key] = (Date(), result)
        return result
    }
}
