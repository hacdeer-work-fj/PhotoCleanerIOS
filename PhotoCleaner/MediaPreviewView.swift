import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import WebKit

struct MediaPreviewView: View {
    let item: PhotoItem
    let isActive: Bool
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        switch item.mediaKind {
        case .photo:
            PhotoImageView(item: item, contentMode: .fit, viewModel: viewModel)
        case .gif:
            GIFPreviewView(item: item, viewModel: viewModel)
        case .livePhoto:
            LivePhotoPreviewView(item: item, viewModel: viewModel)
        case .video:
            VideoPreviewView(item: item, isActive: isActive, viewModel: viewModel)
        }
    }
}

struct GIFPreviewView: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var gifData: Data?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let gifData {
                GIFWebView(data: gifData)
            } else {
                PhotoImageView(item: item, contentMode: .fit, viewModel: viewModel)
            }

            Label("GIF", systemImage: "repeat")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.black.opacity(0.42), in: Capsule())
                .padding(10)
        }
        .onAppear {
            loadGIFData()
        }
        .onChange(of: item.id) { _ in
            gifData = nil
            loadGIFData()
        }
    }

    private func loadGIFData() {
        viewModel.requestGIFData(for: item) { data in
            DispatchQueue.main.async {
                gifData = data
            }
        }
    }
}

struct GIFWebView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.load(data, mimeType: "image/gif", characterEncodingName: "UTF-8", baseURL: URL(fileURLWithPath: "/"))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.load(data, mimeType: "image/gif", characterEncodingName: "UTF-8", baseURL: URL(fileURLWithPath: "/"))
    }
}

struct LivePhotoPreviewView: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var livePhoto: PHLivePhoto?
    @State private var isPlaying = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
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
    let isActive: Bool
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var player = AVPlayer()
    @State private var loadedID: String?
    @State private var timeObserver: Any?
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var isPlaying = false
    @State private var isScrubbing = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                PlayerLayerView(player: player)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        togglePlayback()
                    }

                if loadedID != item.id {
                    ProgressView()
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
            loadPlayerItemIfNeeded()
            updatePlaybackForVisibility()
        }
        .onDisappear {
            pause()
            removeTimeObserver()
        }
        .onChange(of: item.id) { _ in
            resetPlayer()
            loadPlayerItemIfNeeded()
            updatePlaybackForVisibility()
        }
        .onChange(of: isActive) { _ in
            updatePlaybackForVisibility()
        }
    }

    private func loadPlayerItemIfNeeded() {
        guard loadedID != item.id else { return }

        viewModel.requestPlayerItem(for: item) { playerItem in
            DispatchQueue.main.async {
                guard loadedID != item.id else { return }
                player.replaceCurrentItem(with: playerItem)
                loadedID = item.id
                duration = playerItem.flatMap { CMTimeGetSeconds($0.asset.duration) }.flatMap { $0.isFinite ? $0 : nil } ?? 0
                addTimeObserver()
                updatePlaybackForVisibility()
            }
        }
    }

    private func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    private func updatePlaybackForVisibility() {
        if isActive && loadedID == item.id {
            play()
        } else {
            pause()
        }
    }

    private func play() {
        player.play()
        isPlaying = true
    }

    private func pause() {
        player.pause()
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
