import Foundation

enum Store {
    static var root: URL {
        if Launch.testing {
            let t = FileManager.default.temporaryDirectory.appendingPathComponent("warranty-ui", isDirectory: true)
            try? FileManager.default.createDirectory(at: t, withIntermediateDirectories: true)
            return t
        }
        if let g = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Launch.group) { return g }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var stateURL: URL { root.appendingPathComponent("state.json") }
    static var images: URL { folder("Images") }
    static var inbox: URL { folder("Inbox") }

    static func folder(_ name: String) -> URL {
        let u = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func load() -> AppState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? decoder.decode(AppState.self, from: data)
    }

    static func save(_ state: AppState) throws {
        if Launch.testFlag("-save-error") { throw WarrantyError.save }
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func reset() {
        try? FileManager.default.removeItem(at: root)
        _ = folder("Images"); _ = folder("Inbox")
    }

    static func writeImage(_ data: Data) throws -> String {
        let name = UUID().uuidString + ".jpg"
        try data.write(to: images.appendingPathComponent(name), options: .atomic)
        return name
    }

    static func imageURL(_ name: String) -> URL { images.appendingPathComponent(name) }

    static func removeImages(_ names: [String]) {
        for n in names { try? FileManager.default.removeItem(at: imageURL(n)) }
    }

    static func inboxFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        return files.filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
