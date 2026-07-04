import Foundation
import Photos
import SwiftUI

struct PhotoItem: Identifiable {
    let id: String
    let asset: PHAsset
}

final class PhotoLibraryViewModel: NSObject, ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var allItems: [PhotoItem] = []
    @Published private(set) var visibleItems: [PhotoItem] = []
    @Published private(set) var trashItems: [PhotoItem] = []
    @Published var currentIndex: Int = 0
    @Published var selectedTrashIDs: Set<String> = []
    @Published var isBusy = false
    @Published var alertMessage: String?

    private let imageManager = PHCachingImageManager()
    private let previewCache = NSCache<NSString, UIImage>()
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let trashStore: TrashStore
    private var trashIDs: Set<String>

    override init() {
        self.authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.trashStore = TrashStore()
        self.trashIDs = trashStore.load()
        super.init()
        configureCaches()
    }

    init(trashStore: TrashStore) {
        self.authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.trashStore = trashStore
        self.trashIDs = trashStore.load()
        super.init()
        configureCaches()
    }

    var hasPhotoAccess: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    var isAllTrashSelected: Bool {
        !trashItems.isEmpty && selectedTrashIDs.count == trashItems.count
    }

    func requestAccessAndLoad() {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = current

        if current == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                DispatchQueue.main.async {
                    self?.authorizationStatus = newStatus
                    if newStatus == .authorized || newStatus == .limited {
                        self?.loadPhotos()
                    }
                }
            }
            return
        }

        if hasPhotoAccess {
            loadPhotos()
        }
    }

    func loadPhotos() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        let result = PHAsset.fetchAssets(with: options)
        var items: [PhotoItem] = []
        items.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            items.append(PhotoItem(id: asset.localIdentifier, asset: asset))
        }

        let validIDs = Set(items.map(\.id))
        trashIDs = trashIDs.intersection(validIDs)
        trashStore.save(trashIDs)

        allItems = items
        rebuildLists()
    }

    func moveCurrentPhotoToTrash() {
        guard visibleItems.indices.contains(currentIndex) else { return }
        let removedItem = visibleItems.remove(at: currentIndex)
        trashIDs.insert(removedItem.id)
        trashItems.insert(removedItem, at: 0)
        trashStore.save(trashIDs)

        if visibleItems.isEmpty {
            currentIndex = 0
        } else {
            currentIndex = min(currentIndex, visibleItems.count - 1)
        }
    }

    func restoreSelectedTrashItems() {
        trashIDs.subtract(selectedTrashIDs)
        selectedTrashIDs.removeAll()
        trashStore.save(trashIDs)
        rebuildLists()
    }

    func toggleTrashSelection(_ id: String) {
        if selectedTrashIDs.contains(id) {
            selectedTrashIDs.remove(id)
        } else {
            selectedTrashIDs.insert(id)
        }
    }

    func setAllTrashSelected(_ selected: Bool) {
        selectedTrashIDs = selected ? Set(trashItems.map(\.id)) : []
    }

    func permanentlyDeleteSelectedTrashItems() {
        let ids = selectedTrashIDs
        guard !ids.isEmpty else { return }
        isBusy = true

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets)
        }) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBusy = false

                if success {
                    self.trashIDs.subtract(ids)
                    self.selectedTrashIDs.removeAll()
                    self.trashStore.save(self.trashIDs)
                    self.loadPhotos()
                } else {
                    self.alertMessage = error?.localizedDescription ?? "删除失败，请稍后再试。"
                }
            }
        }
    }

    func requestImage(for item: PhotoItem, targetSize: CGSize, mode: PhotoImageRequestMode, completion: @escaping (UIImage?) -> Void) {
        let scale = UIScreen.main.scale
        let minimumPixelSize = mode == .thumbnail ? 120.0 : 300.0
        let pixelSize = CGSize(
            width: max(targetSize.width * scale, minimumPixelSize),
            height: max(targetSize.height * scale, minimumPixelSize)
        )
        let cacheKey = "\(item.id)-\(Int(pixelSize.width))x\(Int(pixelSize.height))-\(mode.rawValue)" as NSString
        let cache = mode == .thumbnail ? thumbnailCache : previewCache

        if let cachedImage = cache.object(forKey: cacheKey) {
            completion(cachedImage)
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = mode == .thumbnail ? .fastFormat : .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        imageManager.requestImage(
            for: item.asset,
            targetSize: pixelSize,
            contentMode: mode == .thumbnail ? .aspectFill : .aspectFit,
            options: options
        ) { image, _ in
            if let image {
                cache.setObject(image, forKey: cacheKey)
            }
            completion(image)
        }
    }

    private func configureCaches() {
        previewCache.countLimit = 12
        thumbnailCache.countLimit = 400
    }

    private func rebuildLists() {
        visibleItems = allItems.filter { !trashIDs.contains($0.id) }
        trashItems = allItems.filter { trashIDs.contains($0.id) }
        selectedTrashIDs = selectedTrashIDs.intersection(Set(trashItems.map(\.id)))

        if visibleItems.isEmpty {
            currentIndex = 0
        } else {
            currentIndex = min(currentIndex, visibleItems.count - 1)
        }
    }
}

enum PhotoImageRequestMode: String {
    case preview
    case thumbnail
}
