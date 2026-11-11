import SwiftUI
import UIKit
import WebKit

/// A DiceBear style the character screen offers.
struct CharacterStyle: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let creator: String
    let license: String
    /// Whether its hairstyles are split into male and female ones.
    let sortedByGender: Bool
}

/// One thing a person can choose, such as hair or skin color, and its possible values.
struct OptionGroup: Decodable, Equatable, Identifiable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case choice = "enum"
        case color
    }

    let name: String
    let kind: Kind
    let values: [String]
    /// The part whose page it is shown on: `hairColor` is on the `hair` page.
    let page: String
    var id: String { name }
}

enum CharacterGender: String, CaseIterable, Sendable {
    case male
    case female
}

/// Draws DiceBear characters and knows which options each style has.
@MainActor
protocol AvatarRendering: AnyObject, Sendable {
    func styles() async throws -> [CharacterStyle]
    func groups(style: String, gender: CharacterGender) async throws -> [OptionGroup]
    /// Fills in or fixes every option so the avatar is valid for its style and gender.
    func normalise(_ avatar: Avatar, gender: CharacterGender) async throws -> Avatar
    func random(style: String, gender: CharacterGender) async throws -> Avatar
    func image(for avatar: Avatar, pixels: Int) async throws -> UIImage
}

enum AvatarRendererError: Error {
    case missingBundle
    case badResult
}

/// Runs the bundled DiceBear JavaScript (`dicebear.js`, built by `tools/dicebear`) in a hidden
/// web view, because DiceBear has no Swift library. Images are cached by avatar and size.
///
/// Only Objective-C WebKit calls are used: `callAsyncJavaScript`'s Swift form lives in a WebKit
/// Swift library that iOS 18 lacks, and linking it makes the app crash at launch there. So each
/// call goes out with `evaluateJavaScript` and its answer comes back as a script message.
@MainActor
final class DiceBearRenderer: NSObject, AvatarRendering, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = DiceBearRenderer()

    private let webView: WKWebView
    private var loading: Task<Void, Error>?
    private var loaded: CheckedContinuation<Void, Error>?
    private var pending: [Int: CheckedContinuation<String, Error>] = [:]
    private var nextID = 0
    private let cache = NSCache<NSString, UIImage>()
    private var cachedStyles: [CharacterStyle]?

    override private init() {
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 16, height: 16), configuration: configuration)
        super.init()
        configuration.userContentController.add(self, name: "stoop")
        webView.navigationDelegate = self
        cache.countLimit = 600
    }

    func styles() async throws -> [CharacterStyle] {
        if let cachedStyles { return cachedStyles }
        let styles: [CharacterStyle] = try decode(try await invoke("catalog", []))
        cachedStyles = styles
        return styles
    }

    func groups(style: String, gender: CharacterGender) async throws -> [OptionGroup] {
        try decode(try await invoke("groups", [style, gender.rawValue]))
    }

    func normalise(_ avatar: Avatar, gender: CharacterGender) async throws -> Avatar {
        let options: [String: String] = try decode(try await invoke("normalise", [avatar.style, gender.rawValue, avatar.options]))
        return Avatar(style: avatar.style, options: options)
    }

    func random(style: String, gender: CharacterGender) async throws -> Avatar {
        let options: [String: String] = try decode(try await invoke("random", [style, gender.rawValue]))
        return Avatar(style: style, options: options)
    }

    func image(for avatar: Avatar, pixels: Int) async throws -> UIImage {
        let key = Self.cacheKey(avatar, pixels) as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let base64: String = try decode(try await invoke("png", [avatar.style, avatar.options, pixels]))
        guard let data = Data(base64Encoded: base64), let image = UIImage(data: data, scale: 1) else {
            throw AvatarRendererError.badResult
        }
        cache.setObject(image, forKey: key)
        return image
    }

    static func cacheKey(_ avatar: Avatar, _ pixels: Int) -> String {
        let options = avatar.options.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return "\(avatar.style)|\(options)|\(pixels)"
    }

    // MARK: JavaScript bridge

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    /// Calls `StoopAvatars[method](...arguments)` and returns its result as JSON.
    private func invoke(_ method: String, _ arguments: [Any]) async throws -> String {
        try await ensureLoaded()
        let json = String(decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self)
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            webView.evaluateJavaScript("StoopAvatars.run(\(id), '\(method)', \(json)); true") { [weak self] _, error in
                guard let error else { return }
                Task { @MainActor in self?.pending.removeValue(forKey: id)?.resume(throwing: error) }
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let id = body["id"] as? Int,
              let continuation = pending.removeValue(forKey: id) else { return }
        if let result = body["result"] as? String {
            continuation.resume(returning: result)
        } else {
            continuation.resume(throwing: AvatarRendererError.badResult)
        }
    }

    private func ensureLoaded() async throws {
        if let loading { return try await loading.value }
        let task = Task { try await self.load() }
        loading = task
        do {
            try await task.value
        } catch {
            loading = nil
            throw error
        }
    }

    private func load() async throws {
        guard let url = Bundle.main.url(forResource: "dicebear", withExtension: "js") else {
            throw AvatarRendererError.missingBundle
        }
        let script = try String(contentsOf: url, encoding: .utf8)
        webView.configuration.userContentController.addUserScript(
            WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loaded = continuation
            webView.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: error)
        loaded = nil
    }
}

extension EnvironmentValues {
    /// Set in previews and tests; views fall back to `DiceBearRenderer.shared`.
    @Entry var avatarRenderer: (any AvatarRendering)? = nil
}
