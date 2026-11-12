import Foundation
import Testing
import UIKit
@testable import PlaceRating

private let me = "11111111-1111-1111-1111-111111111111"
private let day = Date(timeIntervalSince1970: 1_800_000_000)

private func photo(_ id: String, by userId: String = "other", kind: PhotoKind = .place) -> PlacePhoto {
    PlacePhoto(id: id, kind: kind, url: URL(string: "http://test/photos/p/\(id).jpg")!,
               thumbnailUrl: URL(string: "http://test/photos/p/\(id)-thumb.jpg")!, width: 800, height: 600,
               createdAt: day, user: PublicUser(id: userId, username: "u", displayName: "U", avatar: nil))
}

private func imageData(width: CGFloat = 40, height: CGFloat = 20) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
        UIColor.orange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

final class FakePhotosAPI: PhotosAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var pages: [String: PhotoPage] = [:]
    var failAdd: Error?

    var calls: [String] { lock.withLock { _calls } }
    private func log(_ call: String) { lock.withLock { _calls.append(call) } }

    func photos(placeId: String, kind: PhotoKind?, cursor: String?) async throws -> PhotoPage {
        let key = "\(kind?.rawValue ?? "all") \(cursor ?? "-")"
        log("list \(key)")
        return pages[key] ?? PhotoPage(items: [], nextCursor: nil)
    }

    func addPhoto(placeId: String, kind: PhotoKind, jpeg: Data) async throws -> PlacePhoto {
        log("add \(kind.rawValue) jpeg=\(jpeg.starts(with: [0xFF, 0xD8]))")
        if let failAdd { throw failAdd }
        return photo("new", by: me, kind: kind)
    }

    func deletePhoto(placeId: String, photoId: String) async throws { log("delete \(photoId)") }
}

struct PhotoDecodingTests {
    @Test func readsAPhoto() throws {
        let json = """
        {"id":"ph1","kind":"menu","url":"http://localhost:3000/photos/p1/a.jpg","thumbnailUrl":"http://localhost:3000/photos/p1/a-thumb.jpg",
        "width":1600,"height":1200,"createdAt":"2026-11-11T06:54:12.345Z",
        "user":{"id":"u2","username":"sara","displayName":"Sara","avatar":null}}
        """
        let decoded = try JSONDecoder.api.decode(PlacePhoto.self, from: Data(json.utf8))
        #expect(decoded.kind == .menu)
        #expect(decoded.thumbnailUrl.lastPathComponent == "a-thumb.jpg")
    }

    @Test func turnsAnyPickedImageIntoASmallerJPEG() throws {
        let jpeg = try #require(PlacePhotosViewModel.preparedJPEG(from: imageData(width: 400, height: 200), maxSide: 100))
        #expect(jpeg.starts(with: [0xFF, 0xD8]))
        let size = try #require(UIImage(data: jpeg)?.size)
        #expect(size == CGSize(width: 100, height: 50))
        #expect(PlacePhotosViewModel.preparedJPEG(from: Data("not an image".utf8)) == nil)
    }
}

final class FakePhotoSaver: PhotoSaving, @unchecked Sendable {
    var saved: [URL] = []
    var error: Error?
    func save(_ url: URL) async throws {
        if let error { throw error }
        saved.append(url)
    }
}

@MainActor
struct PlacePhotosViewModelTests {
    @Test func savesAnyonesPhotoAndExplainsADeniedPermission() async {
        let saver = FakePhotoSaver()
        let model = PlacePhotosViewModel(placeId: "p1", api: FakePhotosAPI(), myId: me, saver: saver)
        let theirs = photo("theirs")

        await model.save(theirs)
        #expect(saver.saved == [theirs.url])
        #expect(model.savedId == "theirs")
        #expect(model.savingId == nil)

        saver.error = PhotoSaveError.notAllowed
        await model.save(theirs)
        #expect(model.savedId == nil)
        #expect(model.saveError == "Allow Stoop to add photos in Settings to save them.")
    }

    @Test func loadsEachKindAndPages() async {
        let api = FakePhotosAPI()
        api.pages = ["place -": PhotoPage(items: [photo("1")], nextCursor: "c2"),
                     "place c2": PhotoPage(items: [photo("2")], nextCursor: nil),
                     "menu -": PhotoPage(items: [photo("m", kind: .menu)], nextCursor: nil)]
        let model = PlacePhotosViewModel(placeId: "p1", api: api, myId: me)

        await model.load()
        #expect(model.photos.map(\.id) == ["1"])
        #expect(model.hasMore)
        await model.loadMore()
        #expect(model.photos.map(\.id) == ["1", "2"])
        #expect(!model.hasMore)

        model.kind = .menu
        await model.load()
        #expect(model.photos.map(\.id) == ["m"])
    }

    @Test func addingUploadsAJPEGOfTheOpenKindAndShowsItFirst() async {
        let api = FakePhotosAPI()
        api.pages = ["menu -": PhotoPage(items: [photo("m", kind: .menu)], nextCursor: nil)]
        let model = PlacePhotosViewModel(placeId: "p1", api: api, myId: me)
        model.kind = .menu
        await model.load()

        await model.add(imageData: imageData())

        #expect(api.calls.contains("add menu jpeg=true"))
        #expect(model.photos.map(\.id) == ["new", "m"])
        #expect(!model.isUploading)
    }

    @Test func aBadFileOrAFailedUploadShowsAnError() async {
        let api = FakePhotosAPI()
        let model = PlacePhotosViewModel(placeId: "p1", api: api, myId: me)

        await model.add(imageData: Data("nope".utf8))
        #expect(model.errorText != nil)
        #expect(!api.calls.contains { $0.hasPrefix("add") })

        api.failAdd = APIError(status: 422, code: "invalid_image", message: "")
        await model.add(imageData: imageData())
        #expect(model.errorText == "That photo couldn't be used. Try another one.")
        #expect(model.photos.isEmpty)
    }

    @Test func deletesOnlyMyOwnPhotos() async {
        let api = FakePhotosAPI()
        api.pages = ["place -": PhotoPage(items: [photo("mine", by: me), photo("theirs")], nextCursor: nil)]
        let model = PlacePhotosViewModel(placeId: "p1", api: api, myId: me)
        await model.load()

        await model.delete(model.photos[1])
        #expect(!api.calls.contains { $0.hasPrefix("delete") })

        await model.delete(model.photos[0])
        #expect(api.calls.last == "delete mine")
        #expect(model.photos.map(\.id) == ["theirs"])
    }

    @Test func hidesPhotosFromPeopleYouBlock() async {
        let api = FakePhotosAPI()
        api.pages = ["place -": PhotoPage(items: [photo("1", by: "pest"), photo("2", by: "friend")], nextCursor: nil)]
        let moderation = FakeModerationAPI()
        let safety = SafetyViewModel(api: moderation)
        let model = PlacePhotosViewModel(placeId: "p1", api: api, myId: me, safety: safety)
        await model.load()
        #expect(model.photos.map(\.id) == ["1", "2"])

        await safety.block(PublicUser(id: "pest", username: "pest", displayName: "Pest", avatar: nil))
        #expect(model.photos.map(\.id) == ["2"])
    }
}
