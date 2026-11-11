import CoreLocation
import Foundation

/// The `/live` wire format (live-protocol.md): `{ "t": type, "d": data }` as JSON text.
/// Pure functions, so the protocol can be tested without a socket. Never logs coordinates.
enum LiveFrame {
    /// Turns a frame from the server into an event, or nil for frames the app ignores
    /// (`error` frames, unknown types, anything that doesn't parse).
    static func decode(_ text: String, receivedAt: Date) -> LiveEvent? {
        guard let data = text.data(using: .utf8),
              let type = try? JSONDecoder().decode(TypeOnly.self, from: data).t else { return nil }
        func payload<T: Decodable>(_: T.Type) -> T? {
            try? JSONDecoder().decode(Frame<T>.self, from: data).d
        }
        switch type {
        case "hello":
            return payload(Hello.self).map { .hello(ghost: $0.ghost, friends: $0.friends.map { $0.fix(receivedAt: receivedAt) }) }
        case "loc":
            return payload(Position.self).map { .loc($0.fix(receivedAt: receivedAt)) }
        case "gone":
            return payload(Gone.self).map { .gone(userId: $0.userId) }
        case "ghost":
            return payload(Ghost.self).map { .ghost($0.on) }
        default:
            return nil
        }
    }

    /// Your position. `heading` is -1 when the course is unknown, as the server expects.
    static func location(_ location: CLLocation, now: Date) -> String {
        encode(Outgoing(t: "loc", d: LocationData(
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy,
            heading: location.course >= 0 ? location.course : -1,
            ts: Int((now.timeIntervalSince1970 * 1000).rounded())
        )))
    }

    static func ghost(_ on: Bool) -> String {
        encode(Outgoing(t: "ghost", d: GhostData(on: on)))
    }

    // MARK: wire types

    private struct TypeOnly: Decodable { let t: String }
    private struct Frame<D: Decodable>: Decodable { let d: D }

    private struct Hello: Decodable {
        let ghost: Bool
        let friends: [Position]
    }

    private struct Position: Decodable {
        let userId: String
        let lat: Double
        let lng: Double
        let heading: Double?

        func fix(receivedAt: Date) -> FriendFix {
            FriendFix(
                userId: userId, latitude: lat, longitude: lng,
                heading: (heading ?? -1) >= 0 ? heading : nil,
                receivedAt: receivedAt
            )
        }
    }

    private struct Gone: Decodable { let userId: String }
    private struct Ghost: Decodable { let on: Bool }

    private struct Outgoing<D: Encodable>: Encodable {
        let t: String
        let d: D
    }

    private struct LocationData: Encodable {
        let lat: Double
        let lng: Double
        let accuracy: Double
        let heading: Double
        let ts: Int
    }

    private struct GhostData: Encodable { let on: Bool }

    private static func encode(_ value: some Encodable) -> String {
        // sorted keys: the same frame always looks the same on the wire
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? String(decoding: encoder.encode(value), as: UTF8.self)) ?? "{}"
    }
}
