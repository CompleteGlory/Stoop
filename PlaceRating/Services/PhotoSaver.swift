import CoreTransferable
import Foundation
import Nuke
import Photos
import UniformTypeIdentifiers

/// Puts a place photo into the person's photo library.
protocol PhotoSaving: Sendable {
    func save(_ url: URL) async throws
}

enum PhotoSaveError: Error, Equatable {
    /// The person said no to adding photos (or it is restricted).
    case notAllowed
}

/// Asks for add-only access, which can't read the library, then saves the bytes as they came from the server.
struct PhotoLibrarySaver: PhotoSaving {
    func save(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PhotoSaveError.notAllowed }
        let data = try await PhotoBytes.load(url)
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }
}

/// A photo handed to the share sheet as a JPEG, so WhatsApp, Instagram and Files get the image itself.
struct SharedPhoto: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { photo in
            try await PhotoBytes.load(photo.url)
        }
        .suggestedFileName("Stoop photo.jpg")
    }
}

enum PhotoBytes {
    /// The original bytes, from Nuke's disk cache when the viewer already showed the photo.
    static func load(_ url: URL) async throws -> Data {
        try await ImagePipeline.shared.data(for: ImageRequest(url: url)).0
    }
}
