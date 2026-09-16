import Foundation

struct CatalogCourse: Codable, Identifiable {
    var id: UUID
    var name: String
    var locality: String
    var address: String
    var latitude: Double
    var longitude: Double
    var definition: GolfCourse?
    var point: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }
}

