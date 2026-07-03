import SwiftUI

struct TrashView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Binding var confirmingPermanentDelete: Bool
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 104), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.trashItems.isEmpty {
                    EmptyStateView(
                        title: "回收站为空",
                        systemImage: "tray",
                        message: "主界面点删除后，照片会先放到这里。"
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(viewModel.trashItems) { item in
                                TrashThumbnailView(
                                    item: item,
                                    isSelected: viewModel.selectedTrashIDs.contains(item.id),
                                    viewModel: viewModel
                                )
                                .onTapGesture {
                                    viewModel.toggleTrashSelection(item.id)
                                }
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle("回收站")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(viewModel.isAllTrashSelected ? "取消全选" : "全选") {
                        viewModel.setAllTrashSelected(!viewModel.isAllTrashSelected)
                    }
                    .disabled(viewModel.trashItems.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                TrashActionBar(
                    viewModel: viewModel,
                    confirmingPermanentDelete: $confirmingPermanentDelete
                )
            }
            .overlay {
                if viewModel.isBusy {
                    ZStack {
                        Color.black.opacity(0.18).ignoresSafeArea()
                        ProgressView("正在删除")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

struct TrashThumbnailView: View {
    let item: PhotoItem
    let isSelected: Bool
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PhotoImageView(item: item, contentMode: .fill, viewModel: viewModel)
                .frame(height: 124)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                }

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.white)
                .shadow(radius: 2)
                .padding(6)
        }
        .contentShape(Rectangle())
    }
}

struct TrashActionBar: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Binding var confirmingPermanentDelete: Bool

    var body: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 12) {
                Button {
                    viewModel.restoreSelectedTrashItems()
                } label: {
                    Label("恢复", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedTrashIDs.isEmpty || viewModel.isBusy)

                Button(role: .destructive) {
                    confirmingPermanentDelete = true
                } label: {
                    Label("永久删除", systemImage: "trash.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedTrashIDs.isEmpty || viewModel.isBusy)
            }
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.bar)
    }
}
