import XCTest
@testable import PhotoCleaner

final class TrashStoreTests: XCTestCase {
    func testSaveAndLoadIdentifiers() {
        let storage = MemoryKeyValueStore()
        let store = TrashStore(storage: storage)

        store.save(["b", "a"])

        XCTAssertEqual(store.load(), Set(["a", "b"]))
        XCTAssertEqual(storage.values["photoCleaner.trashIdentifiers"] as? [String], ["a", "b"])
    }
}

private final class MemoryKeyValueStore: KeyValueStoring {
    var values: [String: Any] = [:]

    func stringArray(forKey defaultName: String) -> [String]? {
        values[defaultName] as? [String]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }
}
