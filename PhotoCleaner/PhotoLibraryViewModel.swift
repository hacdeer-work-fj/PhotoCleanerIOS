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
    private let trashStore: TrashStore
    private var trashIDs: Set<String>

    override init() {
        self.authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.trashStore = TrashStore()
        self.trashIDs = trashStore.load()
        super.init()
    }

    init(trashStore: TrashStore) {
        self.authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.trashStore = trashStore
        self.trashIDs = trashStore.load()
        super.init()
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
        let id = visibleItems[currentIndex].id
        trashIDs.insert(id)
        trashStore.save(trashIDs)
        rebuildLists()
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

    func requestImage(for item: PhotoItem, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let scale = UIScreen.main.scale
        let pixelSize = CGSize(width: max(targetSize.width * scale, 300), height: max(targetSize.height * scale, 300))

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        imageManager.requestImage(
            for: item.asset,
            targetSize: pixelSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            completion(image)
        }
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
