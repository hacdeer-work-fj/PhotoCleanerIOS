import XCTest
@testable import PhotoCleaner

final class VideoPlaybackStateTests: XCTestCase {
    func testLoadedCurrentVideoStartsPlaying() {
        var state = VideoPlaybackState(itemID: "video-1", activeID: "video-1")

        state.markLoaded(duration: 12)

        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.duration, 12)
    }

    func testSwitchingAwayStopsAndResetsPlayback() {
        var state = VideoPlaybackState(itemID: "video-1", activeID: "video-1")
        state.markLoaded(duration: 12)
        state.updateCurrentTime(5)

        state.setActiveID("video-2")

        XCTAssertFalse(state.isPlaying)
        XCTAssertEqual(state.currentTime, 0)
    }

    func testToggleOnlyAffectsCurrentLoadedVideo() {
        var state = VideoPlaybackState(itemID: "video-1", activeID: "video-2")
        state.markLoaded(duration: 12)

        state.togglePlayback()

        XCTAssertFalse(state.isPlaying)

        state.setActiveID("video-1")
        XCTAssertTrue(state.isPlaying)

        state.togglePlayback()
        XCTAssertFalse(state.isPlaying)
    }

    func testSeekIsClampedToDuration() {
        var state = VideoPlaybackState(itemID: "video-1", activeID: "video-1")
        state.markLoaded(duration: 12)

        state.seek(to: 20)
        XCTAssertEqual(state.currentTime, 12)

        state.seek(to: -5)
        XCTAssertEqual(state.currentTime, 0)
    }
}
