import Photos
import SwiftUI

struct PhotoImageView: View {
    let item: PhotoItem
    let contentMode: ContentMode
    let requestMode: PhotoImageRequestMode
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var image: UIImage?
    @State private var currentRequestID: String?
    @State private var imageRequestID: PHImageRequestID?

    init(item: PhotoItem, contentMode: ContentMode, requestMode: PhotoImageRequestMode = .preview, viewModel: PhotoLibraryViewModel) {
        self.item = item
        self.contentMode = contentMode
        self.requestMode = requestMode
        self.viewModel = viewModel
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear {
                loadImage(size: proxy.size)
            }
            .onChange(of: item.id) { _ in
                loadImage(size: proxy.size)
            }
            .onDisappear {
                cancelPendingRequest()
            }
        }
    }

    private func loadImage(size: CGSize) {
        let requestedID = item.id
        cancelPendingRequest()
        currentRequestID = requestedID
        image = nil
        imageRequestID = viewModel.requestImage(for: item, targetSize: size, mode: requestMode) { loadedImage in
            DispatchQueue.main.async {
                guard currentRequestID == requestedID else { return }
                imageRequestID = nil
                image = loadedImage
            }
        }
    }

    private func cancelPendingRequest() {
        viewModel.cancelImageRequest(imageRequestID)
        imageRequestID = nil
    }
}
