import CryptoKit
import Foundation

/// Drawn avatars saved as PNGs, so a character is drawn once per device rather than once per launch.
///
/// The key is the avatar's style, options and size: a changed character gets a new key and is
/// drawn fresh, so nothing ever needs invalidating by hand. Files live in Caches, which iOS may
/// empty when space is short; that only costs a redraw.
actor AvatarDiskCache {
    /// Bump when the drawing changes (DiceBear version or `tools/dicebear/entry.js`), to drop old images.
    static let version = "dicebear-9.4.3-v1"
    static let shared = AvatarDiskCache()

    private let directory: URL
    private let maxFiles: Int
    private var writesSincePrune = 0

    init(directory: URL? = nil, maxFiles: Int = 800) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? caches.appending(path: "Avatars/\(Self.version)", directoryHint: .isDirectory)
        self.maxFiles = maxFiles
    }

    func data(for key: String) -> Data? {
        let url = file(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        // touching the file keeps often-used avatars from being pruned
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path())
        return data
    }

    func store(_ data: Data, for key: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file(for: key), options: .atomic)
        } catch {
            return
        }
        writesSincePrune += 1
        if writesSincePrune >= 50 {
            writesSincePrune = 0
            prune()
        }
    }

    /// Removes the least recently used files beyond `maxFiles`.
    func prune() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ), files.count > maxFiles else { return }
        let dated = files.map { url in
            (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for (url, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(files.count - maxFiles) {
            try? fm.removeItem(at: url)
        }
    }

    /// Removes every cached avatar (settings: clear cached images).
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func count() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path()).count) ?? 0
    }

    private func file(for key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(name).png")
    }
}
