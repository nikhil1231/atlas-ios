import CryptoKit
import Foundation

actor StateCache {
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NoodleState", isDirectory: true)
    }
    nonisolated static func scope(backend: URL = AppConfiguration.backendURL, credentials: Credentials) -> String {
        let fields = [backend.absoluteString, credentials.token, credentials.accessID, credentials.accessSecret]
        let data = (try? JSONEncoder().encode(fields)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    func load(scope: String) -> MobileProjection? {
        guard let size = try? file(scope).resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 16 * 1024 * 1024,
              let data = try? Data(contentsOf: file(scope)) else { return nil }
        return try? JSONDecoder().decode(MobileProjection.self, from: data)
    }
    func save(_ value: MobileProjection, scope: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        let data = try JSONEncoder().encode(value)
        guard data.count <= 16 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: file(scope), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func clear() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    private func file(_ scope: String) -> URL { directory.appendingPathComponent(scope + ".json") }
}
