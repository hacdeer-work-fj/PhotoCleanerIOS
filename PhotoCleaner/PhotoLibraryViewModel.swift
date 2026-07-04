import Foundation
import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers

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
    @Published var infoItem: PhotoItem?
    @Published private(set) var photoInfo: PhotoInfo?
    @Published private(set) var isLoadingPhotoInfo = false

    private let imageManager = PHCachingImageManager()
    private let previewCache = NSCache<NSString, UIImage>()
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let byteFormatter = ByteCountFormatter()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
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
        var updatedVisibleItems = visibleItems
        var updatedTrashItems = trashItems
        let removedItem = updatedVisibleItems.remove(at: currentIndex)

        trashIDs.insert(removedItem.id)
        updatedTrashItems.insert(removedItem, at: 0)
        trashStore.save(trashIDs)

        visibleItems = updatedVisibleItems
        trashItems = updatedTrashItems

        if updatedVisibleItems.isEmpty {
            currentIndex = 0
        } else {
            currentIndex = min(currentIndex, updatedVisibleItems.count - 1)
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

    func showInfo(for item: PhotoItem) {
        infoItem = item
        loadInfo(for: item)
    }

    func clearInfo() {
        infoItem = nil
        photoInfo = nil
        isLoadingPhotoInfo = false
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
        byteFormatter.countStyle = .file
    }

    private func loadInfo(for item: PhotoItem) {
        photoInfo = nil
        isLoadingPhotoInfo = true

        let resource = PHAssetResource.assetResources(for: item.asset).first
        let resourceFilename = resource?.originalFilename
        let uti = resource?.uniformTypeIdentifier
        let format = uti.flatMap { UTType($0)?.preferredFilenameExtension?.uppercased() } ?? "未知"

        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true

        item.asset.requestContentEditingInput(with: options) { [weak self] input, _ in
            guard let self else { return }

            var fileSizeText = "未知"
            var exifRows: [PhotoInfoRow] = []

            if let url = input?.fullSizeImageURL {
                if let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let fileSize = values.fileSize {
                    fileSizeText = self.byteFormatter.string(fromByteCount: Int64(fileSize))
                }

                exifRows = Self.exifRows(from: url)
            }

            let createdText = item.asset.creationDate.map { self.dateFormatter.string(from: $0) } ?? "未知"
            let modifiedText = item.asset.modificationDate.map { self.dateFormatter.string(from: $0) } ?? "未知"
            let locationText = item.asset.location.map {
                String(format: "%.5f, %.5f", $0.coordinate.latitude, $0.coordinate.longitude)
            } ?? "无"

            let info = PhotoInfo(
                filename: resourceFilename ?? "未知",
                format: format,
                fileSize: fileSizeText,
                dimensions: "\(item.asset.pixelWidth) x \(item.asset.pixelHeight)",
                created: createdText,
                modified: modifiedText,
                location: locationText,
                exifRows: exifRows
            )

            DispatchQueue.main.async {
                guard self.infoItem?.id == item.id else { return }
                self.photoInfo = info
                self.isLoadingPhotoInfo = false
            }
        }
    }

    private static func exifRows(from url: URL) -> [PhotoInfoRow] {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return []
        }

        var rows: [PhotoInfoRow] = []
        if let camera = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            appendValue(camera[kCGImagePropertyTIFFMake], title: "设备品牌", to: &rows)
            appendValue(camera[kCGImagePropertyTIFFModel], title: "设备型号", to: &rows)
        }

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            appendValue(exif[kCGImagePropertyExifFNumber], title: "光圈", prefix: "f/", to: &rows)
            appendValue(exif[kCGImagePropertyExifExposureTime], title: "快门", suffix: " 秒", to: &rows)
            appendValue(exif[kCGImagePropertyExifISOSpeedRatings], title: "ISO", to: &rows)
            appendValue(exif[kCGImagePropertyExifFocalLength], title: "焦距", suffix: " mm", to: &rows)
            appendValue(exif[kCGImagePropertyExifLensModel], title: "镜头", to: &rows)
            appendValue(exif[kCGImagePropertyExifDateTimeOriginal], title: "拍摄时间", to: &rows)
        }

        return rows
    }

    private static func appendValue(_ value: Any?, title: String, prefix: String = "", suffix: String = "", to rows: inout [PhotoInfoRow]) {
        guard let value else { return }

        if let values = value as? [Any] {
            let text = values.map { "\($0)" }.joined(separator: ", ")
            rows.append(PhotoInfoRow(title: title, value: "\(prefix)\(text)\(suffix)"))
        } else {
            rows.append(PhotoInfoRow(title: title, value: "\(prefix)\(value)\(suffix)"))
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

enum PhotoImageRequestMode: String {
    case preview
    case thumbnail
}

struct PhotoInfo {
    let filename: String
    let format: String
    let fileSize: String
    let dimensions: String
    let created: String
    let modified: String
    let location: String
    let exifRows: [PhotoInfoRow]
}

struct PhotoInfoRow: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}
