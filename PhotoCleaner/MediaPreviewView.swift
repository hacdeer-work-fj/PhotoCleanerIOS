import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import WebKit

struct MediaPreviewView: View {
    let item: PhotoItem
    let activeItemID: String
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        switch item.mediaKind {
        case .photo:
            PhotoOrGIFPreviewView(item: item, viewModel: viewModel)
        case .livePhoto:
            LivePhotoPreviewView(item: item, viewModel: viewModel)
        case .video:
            VideoPreviewView(item: item, activeItemID: activeItemID, viewModel: viewModel)
        }
    }
}

struct PhotoOrGIFPreviewView: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var gifData: Data?
    @State private var checkedID: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let gifData {
                GIFWebView(data: gifData)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PhotoImageView(item: item, contentMode: .fit, viewModel: viewModel)
            }

            if gifData != nil {
                Label("GIF", systemImage: "repeat")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.42), in: Capsule())
                    .padding(10)
            }
        }
        .onAppear {
            loadGIFDataIfNeeded()
        }
        .onChange(of: item.id) { _ in
            gifData = nil
            checkedID = nil
            loadGIFDataIfNeeded()
        }
    }

    private func loadGIFDataIfNeeded() {
        guard checkedID != item.id else { return }
        checkedID = item.id

        viewModel.requestGIFData(for: item) { data in
            DispatchQueue.main.async {
                guard checkedID == item.id else { return }
                gifData = data
            }
        }
    }
}

struct GIFWebView: UIViewRepresentable {
    let data: Data

    final class Coordinator {
        var loadedData: Data?
        var gifURL: URL?

        deinit {
            removeTemporaryGIF()
        }

        func removeTemporaryGIF() {
            if let gifURL {
                try? FileManager.default.removeItem(at: gifURL)
                self.gifURL = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.loadedData != data else { return }
        context.coordinator.loadedData = data
        context.coordinator.removeTemporaryGIF()

        let directoryURL = TemporaryCacheManager.prepareGIFDirectory(additionalBytes: Int64(data.count))
        let gifURL = directoryURL.appendingPathComponent("\(UUID().uuidString).gif")

        do {
            try data.write(to: gifURL, options: .atomic)
            context.coordinator.gifURL = gifURL
        } catch {
            return
        }

        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          <style>
            html, body {
              width: 100%;
              height: 100%;
              margin: 0;
              padding: 0;
              overflow: hidden;
              background: transparent;
            }
            body {
              display: flex;
              align-items: center;
              justify-content: center;
            }
            img {
              max-width: 100vw;
              max-height: 100vh;
              width: auto;
              height: auto;
              object-fit: contain;
            }
          </style>
        </head>
        <body>
          <img src="\(gifURL.lastPathComponent)" alt="">
        </body>
        </html>
        """
        uiView.loadHTMLString(html, baseURL: directoryURL)
    }
}

enum TemporaryCacheManager {
    private static let maxCacheBytes: Int64 = 1_073_741_824
    private static let rootDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoCleanerCache", isDirectory: true)

    static var gifDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent("GIFs", isDirectory: true)
    }

    static var shareDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent("Shares", isDirectory: true)
    }

    static func prepareGIFDirectory(additionalBytes: Int64 = 0) -> URL {
        cleanIfNeeded(additionalBytes: additionalBytes)
        try? FileManager.default.createDirectory(at: gifDirectoryURL, withIntermediateDirectories: true)
        return gifDirectoryURL
    }

    static func prepareShareDirectory() -> URL {
        cleanIfNeeded()
        try? FileManager.default.createDirectory(at: shareDirectoryURL, withIntermediateDirectories: true)
        return shareDirectoryURL
    }

    static func cleanIfNeeded(additionalBytes: Int64 = 0) {
        let fileManager = FileManager.default
        let fileURLs = cacheDirectories.flatMap { directoryURL in
            (try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        }

        let cacheBytes = fileURLs.reduce(Int64(0)) { total, fileURL in
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            let fileBytes = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
            return total + Int64(fileBytes)
        }

        guard cacheBytes + additionalBytes >= maxCacheBytes else { return }

        for fileURL in fileURLs {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private static var cacheDirectories: [URL] {
        [gifDirectoryURL, shareDirectoryURL]
    }
}

struct LivePhotoPreviewView: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var livePhoto: PHLivePhoto?
    @State private var isPlaying = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let livePhoto {
                    LivePhotoPlayer(livePhoto: livePhoto, isPlaying: isPlaying)
                } else {
                    PhotoImageView(item: item, contentMode: .fit, viewModel: viewModel)
                }

                Label("实况", systemImage: "livephoto")
                    .font(.caption2.weight(.semibold))
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.42), in: Circle())
                    .padding(10)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onAppear {
                loadLivePhoto(size: proxy.size)
            }
            .onChange(of: item.id) { _ in
                livePhoto = nil
                loadLivePhoto(size: proxy.size)
            }
            .onLongPressGesture(
                minimumDuration: 0.15,
                pressing: { pressing in
                    isPlaying = pressing
                },
                perform: {}
            )
        }
    }

    private func loadLivePhoto(size: CGSize) {
        viewModel.requestLivePhoto(for: item, targetSize: size) { loadedLivePhoto in
            DispatchQueue.main.async {
                livePhoto = loadedLivePhoto
            }
        }
    }
}

struct LivePhotoPlayer: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let isPlaying: Bool

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        uiView.livePhoto = livePhoto

        if isPlaying {
            uiView.startPlayback(with: .full)
        } else {
            uiView.stopPlayback()
        }
    }
}

struct VideoPreviewView: View {
    let item: PhotoItem
    let activeItemID: String
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var player = AVPlayer()
    @State private var loadedID: String?
    @State private var timeObserver: Any?
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var isPlaying = false
    @State private var isScrubbing = false
    @State private var isLoadingVideo = false
    @State private var videoLoadFailed = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                PlayerLayerView(player: player)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        togglePlayback()
                    }

                if isLoadingVideo && loadedID != item.id {
                    ProgressView()
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

                if videoLoadFailed {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                        Button("重试") {
                            retryLoadingVideo()
                        }
                        .buttonStyle(.bordered)
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                }

                if !isPlaying && loadedID == item.id {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
            }

            VideoProgressBar(
                currentTime: $currentTime,
                duration: duration,
                isScrubbing: $isScrubbing,
                seek: seek(to:)
            )
            .padding(.horizontal, 8)
        }
        .onAppear {
            updatePlaybackForVisibility()
        }
        .onDisappear {
            forceStop()
            removeTimeObserver()
        }
        .onChange(of: item.id) { _ in
            resetPlayer()
            updatePlaybackForVisibility()
        }
        .onChange(of: activeItemID) { _ in
            updatePlaybackForVisibility()
        }
        .onReceive(viewModel.$activeItemID) { _ in
            updatePlaybackForVisibility()
        }
    }

    private func loadPlayerItemIfNeeded() {
        guard loadedID != item.id, !isLoadingVideo else { return }
        let requestedID = item.id
        isLoadingVideo = true
        videoLoadFailed = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            guard requestedID == item.id, loadedID != item.id, isLoadingVideo else { return }
            isLoadingVideo = false
            videoLoadFailed = true
            pause()
        }

        viewModel.requestPlayerItem(for: item) { playerItem in
            DispatchQueue.main.async {
                guard requestedID == item.id else { return }
                guard loadedID != item.id else { return }
                isLoadingVideo = false

                guard let playerItem else {
                    videoLoadFailed = true
                    pause()
                    return
                }

                player.replaceCurrentItem(with: playerItem)
                loadedID = item.id
                duration = {
                    let seconds = CMTimeGetSeconds(playerItem.asset.duration)
                    return seconds.isFinite ? seconds : 0
                }()
                addTimeObserver()
                schedulePlaybackUpdate()
            }
        }
    }

    private func togglePlayback() {
        guard isCurrentVideo else { return }
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    private func updatePlaybackForVisibility() {
        guard isCurrentVideo else {
            forceStop()
            return
        }

        loadPlayerItemIfNeeded()
        if loadedID == item.id && player.currentItem != nil {
            play()
        } else {
            pause()
        }
    }

    private func play() {
        player.playImmediately(atRate: 1.0)
        isPlaying = true
    }

    private func pause() {
        player.pause()
        isPlaying = false
    }

    private func forceStop() {
        player.pause()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = 0
        isPlaying = false
    }

    private func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func addTimeObserver() {
        removeTimeObserver()

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { time in
            guard !isScrubbing else { return }
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite {
                currentTime = seconds
            }

            if let item = player.currentItem {
                let itemDuration = CMTimeGetSeconds(item.duration)
                if itemDuration.isFinite {
                    duration = itemDuration
                }
            }
        }
    }

    private func resetPlayer() {
        pause()
        loadedID = nil
        isLoadingVideo = false
        videoLoadFailed = false
        currentTime = 0
        duration = 0
        player.replaceCurrentItem(with: nil)
    }

    private func removeTimeObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func schedulePlaybackUpdate() {
        updatePlaybackForVisibility()
        let expectedID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard expectedID == item.id, isCurrentVideo else { return }
            updatePlaybackForVisibility()
        }
    }

    private func retryLoadingVideo() {
        loadedID = nil
        videoLoadFailed = false
        isLoadingVideo = false
        player.replaceCurrentItem(with: nil)
        updatePlaybackForVisibility()
    }

    private var isCurrentVideo: Bool {
        activeItemID == item.id && viewModel.activeItemID == item.id
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

struct VideoProgressBar: View {
    @Binding var currentTime: Double
    let duration: Double
    @Binding var isScrubbing: Bool
    let seek: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(formatTime(currentTime))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

            Slider(
                value: $currentTime,
                in: 0...max(duration, 0.1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        seek(currentTime)
                    }
                }
            )

            Text(formatTime(duration))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }

        let totalSeconds = max(Int(seconds.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
