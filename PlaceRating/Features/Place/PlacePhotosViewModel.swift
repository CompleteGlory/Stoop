import Foundation
import Observation
import UIKit

/// A place's photos in the sheet: place shots and menu pages, adding your own, and
/// removing yours or reporting someone else's.
@MainActor
@Observable
final class PlacePhotosViewModel {
    var kind: PhotoKind = .place {
        didSet { if kind != oldValue { Task { await load() } } }
    }
    private var loadedPhotos: [PlacePhoto] = []
    /// What is shown: the loaded photos without anything from people you blocked.
    var photos: [PlacePhoto] { loadedPhotos.filter { !safety.isBlocked($0.user.id) } }
    private(set) var hasMore = false
    private(set) var isLoading = false
    private(set) var isUploading = false
    private(set) var errorText: String?
    let myId: String
    let safety: SafetyViewModel
    private let placeId: String
    private let api: any PhotosAPI
    private var cursor: String?

    init(
        placeId: String,
        api: any PhotosAPI,
        myId: String,
        safety: SafetyViewModel = SafetyViewModel(api: UnavailableModerationAPI())
    ) {
        self.placeId = placeId
        self.api = api
        self.myId = myId
        self.safety = safety
    }

    func load() async {
        let requested = kind
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let page = try await api.photos(placeId: placeId, kind: requested, cursor: nil)
            guard requested == kind else { return } // switched tabs meanwhile
            loadedPhotos = page.items
            cursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }

    func loadMore() async {
        guard let cursor, !isLoading else { return }
        let requested = kind
        isLoading = true
        defer { isLoading = false }
        guard let page = try? await api.photos(placeId: placeId, kind: requested, cursor: cursor),
              requested == kind else { return }
        loadedPhotos += page.items
        self.cursor = page.nextCursor
        hasMore = page.nextCursor != nil
    }

    /// Adds a photo picked from the library, as the kind of the tab that is open.
    func add(imageData: Data) async {
        guard let jpeg = Self.preparedJPEG(from: imageData) else {
            errorText = String(localized: "That photo couldn't be read. Try another one.")
            return
        }
        isUploading = true
        errorText = nil
        defer { isUploading = false }
        do {
            let photo = try await api.addPhoto(placeId: placeId, kind: kind, jpeg: jpeg)
            if photo.kind == kind { loadedPhotos.insert(photo, at: 0) }
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }

    func delete(_ photo: PlacePhoto) async {
        guard photo.user.id == myId else { return }
        do {
            try await api.deletePhoto(placeId: placeId, photoId: photo.id)
            loadedPhotos.removeAll { $0.id == photo.id }
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }

    func isMine(_ photo: PlacePhoto) -> Bool { photo.user.id == myId }

    /// Any picked image (HEIC, PNG, JPEG) as a JPEG of at most 2400 px, small enough for the
    /// API's 10 MB limit. The server re-encodes it again and strips the location data.
    nonisolated static func preparedJPEG(from data: Data, maxSide: CGFloat = 2400) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.85, 0.7, 0.5] {
            if let jpeg = resized.jpegData(compressionQuality: quality), jpeg.count <= 10_000_000 { return jpeg }
        }
        return nil
    }
}
