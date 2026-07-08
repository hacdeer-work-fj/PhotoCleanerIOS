import Foundation

struct VideoPlaybackState: Equatable {
    private(set) var loadedID: String?
    private(set) var activeID: String?
    private(set) var itemID: String
    private(set) var isPlaying = false
    private(set) var currentTime = 0.0
    private(set) var duration = 0.0

    init(itemID: String, activeID: String? = nil) {
        self.itemID = itemID
        self.activeID = activeID
    }

    var isCurrentVideo: Bool {
        activeID == itemID
    }

    mutating func setActiveID(_ id: String?) {
        activeID = id
        if !isCurrentVideo {
            forceStop()
        } else if loadedID == itemID {
            isPlaying = true
        }
    }

    mutating func setItemID(_ id: String) {
        itemID = id
        loadedID = nil
        forceStop()
    }

    mutating func markLoaded(duration: Double) {
        loadedID = itemID
        self.duration = duration.isFinite ? duration : 0
        isPlaying = isCurrentVideo
    }

    mutating func togglePlayback() {
        guard isCurrentVideo, loadedID == itemID else { return }
        isPlaying.toggle()
    }

    mutating func updateCurrentTime(_ seconds: Double) {
        guard seconds.isFinite else { return }
        currentTime = max(seconds, 0)
    }

    mutating func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        currentTime = min(max(seconds, 0), max(duration, 0))
    }

    mutating func forceStop() {
        currentTime = 0
        isPlaying = false
    }
}
