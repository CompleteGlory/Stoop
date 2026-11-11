import Foundation
import Testing
@testable import PlaceRating

struct AvatarDiskCacheTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "avatar-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func storesAndReadsBack() async {
        let cache = AvatarDiskCache(directory: tempDirectory())
        #expect(await cache.data(for: "a") == nil)
        await cache.store(Data([1, 2, 3]), for: "a")
        #expect(await cache.data(for: "a") == Data([1, 2, 3]))
        #expect(await cache.data(for: "b") == nil)
    }

    @Test func aChangedCharacterIsADifferentKey() {
        let before = Avatar(style: "avataaars", options: ["top": "bob", "hairColor": "111111"])
        var after = before
        after.options["hairColor"] = "a55728"
        #expect(DiceBearRenderer.cacheKey(before, 132) != DiceBearRenderer.cacheKey(after, 132))
        #expect(DiceBearRenderer.cacheKey(before, 132) != DiceBearRenderer.cacheKey(before, 64))
        // option order does not matter
        let reordered = Avatar(style: "avataaars", options: ["hairColor": "111111", "top": "bob"])
        #expect(DiceBearRenderer.cacheKey(before, 132) == DiceBearRenderer.cacheKey(reordered, 132))
    }

    @Test func prunesTheLeastRecentlyUsed() async throws {
        let cache = AvatarDiskCache(directory: tempDirectory(), maxFiles: 3)
        for i in 0..<5 {
            await cache.store(Data([UInt8(i)]), for: "k\(i)")
            try await Task.sleep(for: .milliseconds(20))
        }
        _ = await cache.data(for: "k0") // recently used again
        await cache.prune()
        #expect(await cache.count() == 3)
        #expect(await cache.data(for: "k0") != nil)
        #expect(await cache.data(for: "k1") == nil)
        #expect(await cache.data(for: "k4") != nil)
    }
}
