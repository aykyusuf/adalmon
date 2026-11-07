import Foundation

/// `/Library/Application Support/Adalmon/helper-state.json` (root'a ait, 0600).
struct FileStateStore: HelperStateStoring {
    var directory = URL(filePath: "/Library/Application Support/Adalmon", directoryHint: .isDirectory)
    private var url: URL { directory.appending(path: "helper-state.json") }

    func load() -> HelperPersistedState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return HelperCoding.decode(HelperPersistedState.self, from: data)
    }

    func save(_ state: HelperPersistedState) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        try? HelperCoding.encode(state).write(to: url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
