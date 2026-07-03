import Foundation

protocol KeyValueStoring {
    func stringArray(forKey defaultName: String) -> [String]?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: KeyValueStoring {}

struct TrashStore {
    private let key = "photoCleaner.trashIdentifiers"
    private let storage: KeyValueStoring

    init(storage: KeyValueStoring = UserDefaults.standard) {
        self.storage = storage
    }

    func load() -> Set<String> {
        Set(storage.stringArray(forKey: key) ?? [])
    }

    func save(_ identifiers: Set<String>) {
        storage.set(Array(identifiers).sorted(), forKey: key)
    }
}
