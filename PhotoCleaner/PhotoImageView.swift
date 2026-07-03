import Photos
import SwiftUI

struct PhotoImageView: View {
    let item: PhotoItem
    let contentMode: ContentMode
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var image: UIImage?

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
        }
    }

    private func loadImage(size: CGSize) {
        image = nil
        viewModel.requestImage(for: item, targetSize: size) { loadedImage in
            DispatchQueue.main.async {
                image = loadedImage
            }
        }
    }
}
