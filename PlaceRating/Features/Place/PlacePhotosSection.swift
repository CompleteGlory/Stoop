import NukeUI
import PhotosUI
import SwiftUI

/// The place sheet's photos: a Place / Menu switch, a row of thumbnails with an add tile first,
/// and a full-screen viewer.
struct PlacePhotosSection: View {
    let model: PlacePhotosViewModel
    @State private var picked: PhotosPickerItem?
    @State private var viewing: PlacePhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Photos").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.foreground.opacity(0.7))
                Spacer()
                Picker(selection: Binding(get: { model.kind }, set: { model.kind = $0 })) {
                    Text("Place").tag(PhotoKind.place)
                    Text("Menu").tag(PhotoKind.menu)
                } label: {
                    Text("Photo type")
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    addTile
                    ForEach(model.photos) { photo in
                        Button { viewing = photo } label: { Thumbnail(url: photo.thumbnailUrl) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Photo by \(photo.user.name)"))
                            .onAppear {
                                if photo.id == model.photos.last?.id { Task { await model.loadMore() } }
                            }
                    }
                    if model.isLoading && model.photos.isEmpty {
                        ProgressView().tint(Brand.foreground).frame(width: 60, height: Thumbnail.side)
                    }
                }
            }
            .scrollIndicators(.hidden)

            if let error = model.errorText {
                Text(error).font(.footnote).foregroundStyle(Brand.negative.text)
            } else if let notice = model.noticeText {
                Text(notice).font(.footnote).foregroundStyle(Brand.positive.text)
            } else if model.photos.isEmpty && !model.isLoading {
                Text(model.kind == .menu ? String(localized: "No menu photos yet.") : String(localized: "No photos yet."))
                    .font(.footnote).foregroundStyle(Brand.foreground.opacity(0.6))
            }
        }
        .task { await model.load() }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { await model.add(imageData: data) }
                picked = nil
            }
        }
        .fullScreenCover(item: $viewing) { photo in
            PhotoViewer(model: model, photos: model.photos, start: photo)
        }
    }

    private var addTile: some View {
        PhotosPicker(selection: $picked, matching: .images, preferredItemEncoding: .compatible) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Brand.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                if model.isUploading {
                    ProgressView().tint(Brand.accent)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "camera.fill").font(.title3)
                        Text(model.kind == .menu ? String(localized: "Add menu") : String(localized: "Add photo"))
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Brand.accent)
                }
            }
            .frame(width: Thumbnail.side, height: Thumbnail.side)
        }
        .disabled(model.isUploading)
    }
}

private struct Thumbnail: View {
    static let side: CGFloat = 92
    let url: URL

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                Brand.surface.overlay {
                    if state.error != nil { Image(systemName: "photo").foregroundStyle(Brand.foreground.opacity(0.4)) }
                }
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(.rect(cornerRadius: 12))
    }
}

/// Swipe through the photos full screen; delete yours, report anyone else's.
private struct PhotoViewer: View {
    let model: PlacePhotosViewModel
    let photos: [PlacePhoto]
    @State private var current: String
    @State private var confirmingDelete = false
    @State private var choosingReason = false
    @Environment(\.dismiss) private var dismiss

    init(model: PlacePhotosViewModel, photos: [PlacePhoto], start: PlacePhoto) {
        self.model = model
        self.photos = photos
        _current = State(initialValue: start.id)
    }

    private var photo: PlacePhoto? { photos.first { $0.id == current } }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $current) {
                ForEach(photos) { photo in
                    LazyImage(url: photo.url) { state in
                        if let image = state.image {
                            image.resizable().scaledToFit()
                        } else if state.error != nil {
                            Image(systemName: "photo").font(.largeTitle).foregroundStyle(.white.opacity(0.5))
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                    .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.bold)).frame(width: 40, height: 40)
                        .background(.black.opacity(0.5), in: .circle)
                }
                .accessibilityLabel(Text("Close"))
                if let photo {
                    AvatarImage(avatar: photo.user.avatar, size: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: photo.user.name).font(.subheadline.weight(.semibold))
                        Text(photo.createdAt, format: .relative(presentation: .named)).font(.caption).opacity(0.7)
                    }
                }
                Spacer()
                if let photo {
                    Menu {
                        if model.isMine(photo) {
                            Button("Delete photo", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        } else {
                            Button("Report photo", systemImage: "flag") { choosingReason = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.body.weight(.bold)).frame(width: 40, height: 40)
                            .background(.black.opacity(0.5), in: .circle)
                    }
                    .accessibilityLabel(Text("More"))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
        }
        .confirmationDialog(Text("Delete this photo?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete photo", role: .destructive) {
                guard let photo else { return }
                Task {
                    await model.delete(photo)
                    dismiss()
                }
            }
        }
        .confirmationDialog(Text("Why are you reporting this photo?"), isPresented: $choosingReason, titleVisibility: .visible) {
            ForEach(ReportReason.allCases, id: \.self) { reason in
                Button(reason.title) {
                    guard let photo else { return }
                    Task {
                        await model.report(photo, reason: reason)
                        dismiss()
                    }
                }
            }
        }
    }
}

extension ReportReason {
    var title: String {
        switch self {
        case .spam: String(localized: "Spam")
        case .abuse: String(localized: "Abuse or harassment")
        case .inappropriate: String(localized: "Inappropriate")
        case .impersonation: String(localized: "Impersonation")
        case .other: String(localized: "Something else")
        }
    }
}
