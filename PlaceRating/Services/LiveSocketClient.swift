import CoreLocation
import Foundation

/// An access token for the `/live` upgrade request. After the server refused one (HTTP 401 or
/// close code 4401), pass it as `rejected` to get a refreshed one.
protocol LiveAuth: Sendable {
    func liveAccessToken(replacing rejected: String?) async throws -> String
}

extension APIClient: LiveAuth {
    func liveAccessToken(replacing rejected: String?) async throws -> String {
        if let rejected { return try await session.tokenReplacing(rejected) }
        return try await session.validAccessToken()
    }
}

struct UnavailableLiveAuth: LiveAuth {
    func liveAccessToken(replacing rejected: String?) async throws -> String { throw AuthError.sessionExpired }
}

/// One WebSocket connection, as the client needs it. `URLSessionWebSocketTask` in the app,
/// a scripted fake in tests.
protocol LiveConnection: AnyObject, Sendable {
    func send(_ text: String) async throws
    /// The next text frame; throws once the connection is closed or never opened.
    func receive() async throws -> String
    func close()
    /// The server's close code, once `receive` has thrown.
    var closeCode: Int? { get }
    /// The HTTP status when the server refused the upgrade (401 bad token, 403 no username yet).
    var handshakeStatus: Int? { get }
}

protocol LiveConnecting: Sendable {
    func open(_ request: URLRequest) -> any LiveConnection
}

struct URLSessionLiveConnector: LiveConnecting {
    func open(_ request: URLRequest) -> any LiveConnection {
        URLSessionLiveConnection(request: request)
    }
}

final class URLSessionLiveConnection: LiveConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(request: URLRequest, session: URLSession = .shared) {
        task = session.webSocketTask(with: request)
        task.resume()
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let text): text
        case .data(let data): String(decoding: data, as: UTF8.self)
        @unknown default: ""
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }

    var closeCode: Int? {
        let code = task.closeCode.rawValue
        return code > 0 ? code : nil
    }

    var handshakeStatus: Int? {
        (task.response as? HTTPURLResponse)?.statusCode
    }
}

/// The real `/live` connection (live-protocol.md): connects with the access token, reconnects with
/// backoff, and follows the server's close codes. It stays out of the way of the map:
/// everything the app needs arrives as `LiveEvent`s.
@MainActor
final class LiveSocketClient: LiveSocketProtocol {
    /// Close codes the server uses on purpose (live-protocol.md).
    private enum Close {
        static let unauthorized = 4401
        static let deleted = 4403
        static let replaced = 4409
        static let tooManyFrames = 4429
        static let tooManyInvalid = 4400
    }

    /// Seconds to wait after the 1st, 2nd, 3rd... failed try; the last value repeats.
    nonisolated static let backoffSeconds: [Double] = [1, 2, 4, 8, 16, 30]
    /// How long to stay away after the server said we were flooding it.
    static let floodPause: Duration = .seconds(60)

    /// 1, 2, 4, 8, 16, then 30 seconds, each ±20 % (`jitter` is a factor in 0.8...1.2).
    nonisolated static func backoff(attempt: Int, jitter: Double) -> Duration {
        let base = backoffSeconds[min(max(attempt, 0), backoffSeconds.count - 1)]
        return .milliseconds(Int((base * jitter * 1000).rounded()))
    }

    private let url: @Sendable () -> URL
    private let auth: any LiveAuth
    private let connector: any LiveConnecting
    private let pause: @Sendable (Duration) async -> Void
    private let jitter: @Sendable () -> Double
    private let now: @Sendable () -> Date

    private var runner: Task<Void, Never>?
    private var outbox: AsyncStream<String>.Continuation?
    private var connection: (any LiveConnection)?
    private var isReady = false
    /// A ghost choice made while offline (or not yet confirmed), sent as soon as we are connected.
    private var wantedGhost: Bool?

    init(
        url: @escaping @Sendable () -> URL,
        auth: any LiveAuth,
        connector: any LiveConnecting = URLSessionLiveConnector(),
        pause: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        jitter: @escaping @Sendable () -> Double = { .random(in: 0.8...1.2) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.url = url
        self.auth = auth
        self.connector = connector
        self.pause = pause
        self.jitter = jitter
        self.now = now
    }

    func connect() -> AsyncStream<LiveEvent> {
        disconnect()
        let (stream, continuation) = AsyncStream<LiveEvent>.makeStream()
        let task = Task { [weak self] in
            await self?.run(continuation)
            continuation.finish()
        }
        runner = task
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func disconnect() {
        runner?.cancel()
        runner = nil
        outbox?.finish()
        outbox = nil
        connection?.close()
        connection = nil
        isReady = false
    }

    func send(_ location: CLLocation) {
        guard isReady else { return }
        outbox?.yield(LiveFrame.location(location, now: now()))
    }

    func setGhost(_ on: Bool) {
        wantedGhost = on
        if isReady { outbox?.yield(LiveFrame.ghost(on)) }
    }

    // MARK: the connection loop

    private func run(_ events: AsyncStream<LiveEvent>.Continuation) async {
        var attempt = 0
        var refusals = 0
        var rejected: String?

        while !Task.isCancelled {
            let token: String
            do {
                token = try await auth.liveAccessToken(replacing: rejected)
            } catch AuthError.sessionExpired {
                events.yield(.unauthorized)
                return
            } catch {
                // most likely no network while refreshing: try again later
                events.yield(.disconnected)
                await pause(Self.backoff(attempt: attempt, jitter: jitter()))
                attempt += 1
                continue
            }

            var request = URLRequest(url: url())
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let connection = connector.open(request)
            self.connection = connection
            let (frames, writer) = AsyncStream<String>.makeStream()
            outbox = writer
            let sender = Task {
                for await frame in frames { try? await connection.send(frame) }
            }

            var sawHello = false
            do {
                while !Task.isCancelled {
                    let text = try await connection.receive()
                    guard var event = LiveFrame.decode(text, receivedAt: now()) else { continue }
                    switch event {
                    case .hello(let ghost, let friends):
                        sawHello = true
                        attempt = 0
                        refusals = 0
                        rejected = nil
                        if let wanted = wantedGhost, wanted != ghost {
                            // the person chose while we were offline: the server hears it now
                            writer.yield(LiveFrame.ghost(wanted))
                            event = .hello(ghost: wanted, friends: friends)
                        } else {
                            wantedGhost = nil
                        }
                        isReady = true
                    case .ghost(let on):
                        if wantedGhost == on { wantedGhost = nil }
                    default:
                        break
                    }
                    events.yield(event)
                }
            } catch {
                // the connection ended; why is read below
            }

            isReady = false
            writer.finish()
            sender.cancel()
            connection.close()
            if self.connection === connection {
                self.connection = nil
                outbox = nil
            }
            if Task.isCancelled { return }
            events.yield(.disconnected)

            let status = connection.handshakeStatus
            let code = connection.closeCode
            if status == 401 || code == Close.unauthorized {
                // the token was refused: refresh it once and retry, then give up
                refusals += 1
                if refusals >= 2 {
                    events.yield(.unauthorized)
                    return
                }
                rejected = token
                continue
            }
            if status == 403 { return } // no username yet: refreshing won't help
            if code == Close.deleted {
                events.yield(.unauthorized)
                return
            }
            if code == Close.replaced {
                // another device or an older socket of ours took over: stay quiet until the
                // person brings the app back to the foreground
                events.yield(.replaced)
                return
            }

            if code == Close.tooManyFrames || code == Close.tooManyInvalid {
                await pause(Self.floodPause)
            } else {
                await pause(Self.backoff(attempt: attempt, jitter: jitter()))
            }
            if !sawHello { attempt += 1 } else { attempt = 1 }
        }
    }
}
