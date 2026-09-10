import Foundation

enum Environment {
    /// .env is local configuration, never included in the signed app bundle.
    static var fileURL: URL {
        if let explicit = ProcessInfo.processInfo.environment["EMILIA_ENV_FILE"] { return URL(fileURLWithPath: explicit) }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")
        if FileManager.default.fileExists(atPath: cwd.path) { return cwd }
        let development = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".env")
        if FileManager.default.fileExists(atPath: development.path) { return development }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Emilia/.env")
    }
    static func readKey() -> String {
        let saved = KeyStore.read()
        if !saved.isEmpty { return saved }
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty { return key }
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return "" }
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "OPENAI_API_KEY" {
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return ""
    }
}
