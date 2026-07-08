import Photos
import MapKit
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = PhotoLibraryViewModel()
    @State private var showingTrash = false
    @State private var confirmingPermanentDelete = false
    @State private var toastDismissWorkItem: DispatchWorkItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                content

                if let toastMessage = viewModel.toastMessage {
                    ToastView(message: toastMessage.text)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 112)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
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
            .sheet(item: $viewModel.shareItem, onDismiss: {
                viewModel.clearShareItem()
            }) { item in
                ShareSheetView(item: item, viewModel: viewModel)
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
            .animation(.easeInOut(duration: 0.18), value: viewModel.toastMessage?.id)
            .onChange(of: viewModel.toastMessage?.id) { _ in
                scheduleToastDismissal()
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

    private func scheduleToastDismissal() {
        toastDismissWorkItem?.cancel()
        guard viewModel.toastMessage != nil else { return }

        let workItem = DispatchWorkItem {
            viewModel.clearToast()
        }
        toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
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
                        ForEach(viewModel.visibleItems) { item in
                            MediaPreviewView(
                                item: item,
                                activeItemID: viewModel.activeItemID,
                                viewModel: viewModel
                            )
                            .id(item.id)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                            .simultaneousGesture(verticalPageGesture(for: item))
                            .tag(item.id)
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

                    Button {
                        viewModel.showShareSheetForCurrentItem()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .background(.regularMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                Text("\(viewModel.currentIndex + 1) / \(viewModel.visibleItems.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }

            BottomControls(viewModel: viewModel, showingTrash: $showingTrash)
        }
    }

    private func verticalPageGesture(for item: PhotoItem) -> some Gesture {
        DragGesture(minimumDistance: 36)
            .onEnded { value in
                let horizontalDistance = abs(value.translation.width)
                let verticalDistance = abs(value.translation.height)
                let isVerticalIntent = verticalDistance >= 90 && verticalDistance >= horizontalDistance * 1.8

                if isVerticalIntent && value.translation.height < 0 {
                    viewModel.showInfo(for: item)
                } else if isVerticalIntent && value.translation.height > 0 {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        viewModel.jumpToRandomVisibleItem()
                    }
                }
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
    private let thumbnailSlots = 7
    private let thumbnailSize = 58.0
    private let thumbnailSpacing = 8.0

    var body: some View {
        let centerSlot = thumbnailSlots / 2

        ZStack {
            HStack(spacing: thumbnailSpacing) {
                ForEach(0..<thumbnailSlots, id: \.self) { slot in
                    let itemIndex = viewModel.currentIndex + slot - centerSlot

                    if viewModel.visibleItems.indices.contains(itemIndex) {
                        let item = viewModel.visibleItems[itemIndex]
                        ThumbnailCell(item: item, size: thumbnailSize, viewModel: viewModel)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .highPriorityGesture(TapGesture().onEnded {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    viewModel.selectVisibleItem(at: itemIndex)
                                }
                            })
                            .accessibilityAddTraits(.isButton)
                    } else {
                        Color.clear
                            .frame(width: thumbnailSize, height: thumbnailSize)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()

            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.accentColor, lineWidth: 3)
                .frame(width: thumbnailSize + 2, height: thumbnailSize + 2)
                .allowsHitTesting(false)
        }
        .frame(height: 70)
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

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.78), in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

struct ShareSheetView: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var shareURL: URL?
    @State private var didFail = false

    var body: some View {
        Group {
            if let shareURL {
                ActivityView(activityItems: [shareURL])
                    .ignoresSafeArea()
            } else if didFail {
                EmptyStateView(
                    title: "无法分享",
                    systemImage: "square.and.arrow.up",
                    message: "当前内容暂时无法导出给系统分享。"
                )
            } else {
                ProgressView("正在准备分享")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            prepareShareItem()
        }
    }

    private func prepareShareItem() {
        guard shareURL == nil, !didFail else { return }

        viewModel.requestShareURL(for: item) { url in
            if let url {
                shareURL = url
            } else {
                didFail = true
                viewModel.clearShareItem()
                viewModel.toastMessage = ToastMessage(text: "分享失败，请稍后再试")
            }
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
    private let mapCoordinate: CLLocationCoordinate2D
    @State private var region: MKCoordinateRegion

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        let mapCoordinate = MapCoordinateConverter.displayCoordinate(for: coordinate)
        self.mapCoordinate = mapCoordinate
        self._region = State(initialValue: MKCoordinateRegion(
            center: mapCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    var body: some View {
        Button {
            openInMaps()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Map(coordinateRegion: $region, annotationItems: [PhotoMapPin(coordinate: mapCoordinate)]) { pin in
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
        let placemark = MKPlacemark(coordinate: mapCoordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = "照片位置"
        item.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: mapCoordinate),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        ])
    }
}

struct PhotoMapPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

enum MapCoordinateConverter {
    static func displayCoordinate(for coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInMainlandChina(coordinate) else {
            return coordinate
        }
        return wgs84ToGCJ02(coordinate)
    }

    private static func isInMainlandChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let longitude = coordinate.longitude
        let latitude = coordinate.latitude

        guard longitude >= 73.66, longitude <= 135.05, latitude >= 3.86, latitude <= 53.55 else {
            return false
        }

        if longitude >= 119.0, longitude <= 122.5, latitude >= 21.5, latitude <= 25.5 {
            return false
        }

        if longitude >= 113.7, longitude <= 114.5, latitude >= 22.1, latitude <= 22.6 {
            return false
        }

        return true
    }

    private static func wgs84ToGCJ02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let a = 6378245.0
        let ee = 0.00669342162296594323
        let longitudeOffset = coordinate.longitude - 105.0
        let latitudeOffset = coordinate.latitude - 35.0

        var transformedLatitude = transformLatitude(longitudeOffset, latitudeOffset)
        var transformedLongitude = transformLongitude(longitudeOffset, latitudeOffset)
        let radianLatitude = coordinate.latitude / 180.0 * .pi
        var magic = sin(radianLatitude)
        magic = 1.0 - ee * magic * magic
        let sqrtMagic = sqrt(magic)

        transformedLatitude = (transformedLatitude * 180.0) / ((a * (1.0 - ee)) / (magic * sqrtMagic) * .pi)
        transformedLongitude = (transformedLongitude * 180.0) / (a / sqrtMagic * cos(radianLatitude) * .pi)

        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + transformedLatitude,
            longitude: coordinate.longitude + transformedLongitude
        )
    }

    private static func transformLatitude(_ longitude: Double, _ latitude: Double) -> Double {
        var result = -100.0 + 2.0 * longitude + 3.0 * latitude + 0.2 * latitude * latitude
        result += 0.1 * longitude * latitude + 0.2 * sqrt(abs(longitude))
        result += (20.0 * sin(6.0 * longitude * .pi) + 20.0 * sin(2.0 * longitude * .pi)) * 2.0 / 3.0
        result += (20.0 * sin(latitude * .pi) + 40.0 * sin(latitude / 3.0 * .pi)) * 2.0 / 3.0
        result += (160.0 * sin(latitude / 12.0 * .pi) + 320.0 * sin(latitude * .pi / 30.0)) * 2.0 / 3.0
        return result
    }

    private static func transformLongitude(_ longitude: Double, _ latitude: Double) -> Double {
        var result = 300.0 + longitude + 2.0 * latitude + 0.1 * longitude * longitude
        result += 0.1 * longitude * latitude + 0.1 * sqrt(abs(longitude))
        result += (20.0 * sin(6.0 * longitude * .pi) + 20.0 * sin(2.0 * longitude * .pi)) * 2.0 / 3.0
        result += (20.0 * sin(longitude * .pi) + 40.0 * sin(longitude / 3.0 * .pi)) * 2.0 / 3.0
        result += (150.0 * sin(longitude / 12.0 * .pi) + 300.0 * sin(longitude / 30.0 * .pi)) * 2.0 / 3.0
        return result
    }
}
