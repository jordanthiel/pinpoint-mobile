import ActivityKit
import Foundation

/// A small value snapshot; the extension never reads the database or starts GPS.
struct GolfActivityAttributes: ActivityAttributes {
    typealias ContentState = GolfActivityState
    var roundID: UUID
    var course: String
}
