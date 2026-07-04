import Photos
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
            .navigationTitle("照片快清")
            .navigationBarTitleDisplayMode(.inline)
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
                TabView(selection: $viewModel.currentIndex) {
                    ForEach(Array(viewModel.visibleItems.enumerated()), id: \.element.id) { index, item in
                        PhotoImageView(item: item, contentMode: .fit, viewModel: viewModel)
                            .padding(.horizontal, 10)
                            .tag(index)
                            .gesture(
                                DragGesture(minimumDistance: 28)
                                    .onEnded { value in
                                        if value.translation.height < -70 && abs(value.translation.width) < 80 {
                                            viewModel.showInfo(for: item)
                                        }
                                    }
                            )
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(viewModel.visibleItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                viewModel.currentIndex = index
                            }
                        } label: {
                            PhotoImageView(item: item, contentMode: .fill, requestMode: .thumbnail, viewModel: viewModel)
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(index == viewModel.currentIndex ? Color.accentColor : Color.white.opacity(0.35), lineWidth: index == viewModel.currentIndex ? 3 : 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 2)
            }
            .frame(height: 70)
            .onChange(of: viewModel.currentIndex) { newIndex in
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
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
