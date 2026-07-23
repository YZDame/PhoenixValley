import Foundation
import Observation
import RoadSketchCore

@MainActor
@Observable
final class AppIntentRouter {
    struct Request: Equatable {
        let id = UUID()
        var roadKind: RoadKind? = nil
        var createsNewMap = false

        static func == (lhs: Request, rhs: Request) -> Bool {
            lhs.id == rhs.id
        }
    }

    static let shared = AppIntentRouter()
    private(set) var request: Request?

    private init() {}

    func openCanvas(roadKind: RoadKind?) {
        request = Request(roadKind: roadKind)
    }

    func createRandomMap() {
        request = Request(createsNewMap: true)
    }

    func consumeRequest() -> Request? {
        defer { request = nil }
        return request
    }
}
