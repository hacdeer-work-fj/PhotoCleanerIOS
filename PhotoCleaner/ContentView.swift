import Photos
import MapKit
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = PhotoLibraryViewModel()
    @State private var showingTrash = false
    @State private var confirmingPermanentDelete = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                content
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingTrash) {
                TrashView(
                    viewModel: viewModel,
                    confirmingPermanentDelete: $confirmingPermanentDelete
                )
            }
            .sheet(item: $viewModel.infoItem, onDismiss: {
                viewModel.clearInfo()
            }) { item in
                PhotoInfoView(item: item, viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
            .confirmationDialog(
                "永久删除选中的照片？",
                isPresented: $confirmingPermanentDelete,
                titleVisibility: .visible
            ) {
                Button("永久删除", role: .destructive) {
                    viewModel.permanentlyDeleteSelectedTrashItems()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这会请求系统从相册删除照片，iOS 可能还会弹出确认。")
            }
            .alert("提示", isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(viewModel.alertMessage ?? "")
            }
            .onAppear {
                viewModel.requestAccessAndLoad()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.authorizationStatus {
        case .authorized, .limited:
            PhotoBrowserView(viewModel: viewModel, showingTrash: $showingTrash)
        case .notDetermined:
            ProgressView("正在请求相册权限")
        case .denied, .restricted:
            PermissionDeniedView()
        @unknown default:
            PermissionDeniedView()
        }
    }
}

struct PhotoBrowserView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Binding var showingTrash: Bool

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.visibleItems.isEmpty {
                EmptyStateView(
                    title: "没有可清理的照片",
                    systemImage: "photo.on.rectangle",
                    message: "相册为空，或照片都已经在回收站里。"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .topLeading) {
                    TabView(selection: Binding(
                        get: { viewModel.currentItemID },
                        set: { viewModel.selectVisibleItem(id: $0) }
                    )) {
                        ForEach(Array(viewModel.visibleItems.enumerated()), id: \.element.id) { index, item in
                            MediaPreviewView(
                                item: item,
                                activeItemID: viewModel.activeItemID,
                                viewModel: viewModel
                            )
                                .padding(.horizontal, 10)
                                .tag(item.id)
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 28)
                                        .onEnded { value in
                                            if value.translation.height < -70 && abs(value.translation.width) < 80 {
                                                viewModel.showInfo(for: item)
                                            } else if value.translation.height > 70 && abs(value.translation.width) < 80 {
                                                withAnimation(.easeInOut(duration: 0.18)) {
                                                    viewModel.jumpToRandomVisibleItem()
                                                }
                                            }
                                        }
                                )
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    if viewModel.randomReturnItemID != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                viewModel.returnToRandomSource()
                            }
                        } label: {
                            Image(systemName: "arrow.uturn.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 40, height: 40)
                                .background(.regularMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 16)
                        .padding(.top, 12)
                    }
                }

                Text("\(viewModel.currentIndex + 1) / \(viewModel.visibleItems.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }

            BottomControls(viewModel: viewModel, showingTrash: $showingTrash)
        }
    }
}

struct BottomControls: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Binding var showingTrash: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            if !viewModel.visibleItems.isEmpty {
                ThumbnailStrip(viewModel: viewModel)
                    .padding(.top, 10)
            }

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    viewModel.moveCurrentPhotoToTrash()
                } label: {
                    Label("删除", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.visibleItems.isEmpty)

                Button {
                    showingTrash = true
                } label: {
                    Label("回收站", systemImage: "tray.full")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding()
        }
        .background(.bar)
    }
}

struct ThumbnailStrip: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    private let thumbnailSize = 58.0
    private let thumbnailSpacing = 8.0

    var body: some View {
        GeometryReader { geometry in
            let slots = thumbnailSlots(for: geometry.size.width)
            let centerSlot = slots / 2

            ZStack {
                HStack(spacing: thumbnailSpacing) {
                    ForEach(0..<slots, id: \.self) { slot in
                        let itemIndex = viewModel.currentIndex + slot - centerSlot

                        if viewModel.visibleItems.indices.contains(itemIndex) {
                            let item = viewModel.visibleItems[itemIndex]
                            Button {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    viewModel.selectVisibleItem(at: itemIndex)
                                }
                            } label: {
                                ThumbnailCell(item: item, size: thumbnailSize, viewModel: viewModel)
                                    .id(item.id)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear
                                .frame(width: thumbnailSize, height: thumbnailSize)
                        }
                    }
                }
                .frame(width: geometry.size.width, height: 70)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 18)
                        .onEnded { value in
                            moveByThumbnailDrag(value)
                        }
                )

                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .frame(width: thumbnailSize + 2, height: thumbnailSize + 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 70)
    }

    private func thumbnailSlots(for width: CGFloat) -> Int {
        let rawCount = max(Int((width + thumbnailSpacing) / (thumbnailSize + thumbnailSpacing)), 1)
        return rawCount.isMultiple(of: 2) ? rawCount - 1 : rawCount
    }

    private func moveByThumbnailDrag(_ value: DragGesture.Value) {
        let distance = -value.predictedEndTranslation.width
        let stepWidth = thumbnailSize + thumbnailSpacing
        let rawSteps = Int((distance / stepWidth).rounded())
        let steps = max(min(rawSteps, 8), -8)
        guard steps != 0 else { return }

        let targetIndex = min(max(viewModel.currentIndex + steps, 0), viewModel.visibleItems.count - 1)
        guard targetIndex != viewModel.currentIndex else { return }

        withAnimation(.easeOut(duration: 0.16)) {
            viewModel.selectVisibleItem(at: targetIndex)
        }
    }
}

struct ThumbnailCell: View {
    let item: PhotoItem
    let size: CGFloat
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        PhotoImageView(item: item, contentMode: .fill, requestMode: .thumbnail, viewModel: viewModel)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                MediaBadge(kind: item.mediaKind)
            }
    }
}

struct MediaBadge: View {
    let kind: MediaKind

    var body: some View {
        switch kind {
        case .photo:
            EmptyView()
        case .livePhoto:
            Image(systemName: "livephoto")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.55), in: Circle())
                .padding(4)
        case .video:
            Image(systemName: "play.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(5)
                .background(.black.opacity(0.55), in: Circle())
                .padding(4)
        }
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        EmptyStateView(
            title: "无法访问照片",
            systemImage: "lock",
            message: "请在系统设置里允许访问照片后再打开。"
        )
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PhotoInfoView: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingPhotoInfo {
                    ProgressView("正在读取照片信息")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let info = viewModel.photoInfo {
                    List {
                        Section("文件") {
                            InfoRow(title: "文件名", value: info.filename)
                            InfoRow(title: "格式", value: info.format)
                            InfoRow(title: "大小", value: info.fileSize)
                            InfoRow(title: "尺寸", value: info.dimensions)
                        }

                        Section("时间和位置") {
                            InfoRow(title: "创建时间", value: info.created)
                            InfoRow(title: "修改时间", value: info.modified)
                            InfoRow(title: "位置", value: info.location)

                            if let coordinate = info.coordinate {
                                PhotoLocationMapView(coordinate: coordinate)
                            }
                        }

                        if !info.exifRows.isEmpty {
                            Section("EXIF") {
                                ForEach(info.exifRows) { row in
                                    InfoRow(title: row.title, value: row.value)
                                }
                            }
                        }
                    }
                } else {
                    EmptyStateView(
                        title: "没有读取到信息",
                        systemImage: "info.circle",
                        message: "这张照片没有可显示的文件或 EXIF 信息。"
                    )
                }
            }
            .navigationTitle("照片信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

struct PhotoLocationMapView: View {
    let coordinate: CLLocationCoordinate2D
    @State private var region: MKCoordinateRegion

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        self._region = State(initialValue: MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    var body: some View {
        Button {
            openInMaps()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Map(coordinateRegion: $region, annotationItems: [PhotoMapPin(coordinate: coordinate)]) { pin in
                    MapMarker(coordinate: pin.coordinate, tint: .red)
                }
                .allowsHitTesting(false)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Label("打开地图", systemImage: "map")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(10)
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = "照片位置"
        item.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        ])
    }
}

struct PhotoMapPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
