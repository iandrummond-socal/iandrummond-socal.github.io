import Foundation

/// Reads `Config.plist` (gitignored; copy `Config.example.plist`). Without a real app key the app is local-only.
struct DropboxConfig {
    enum AccessType: String {
        case appFolder
        case fullDropbox
    }

    let appKey: String
    let accessType: AccessType
    let folderOverride: String?

    /// Default folder: an app-folder app already lives inside `/Apps/Notation`, so its root is "".
    var defaultFolder: String {
        if let folderOverride { return DropboxPath.normalize(folderOverride) }
        return accessType == .appFolder ? "" : "/Apps/Notation"
    }

    /// Must be registered in the Dropbox app console under OAuth 2 redirect URIs.
    var redirectURI: String { "db-\(appKey)://1/connect" }
    var callbackScheme: String { "db-\(appKey)" }

    static func load(bundle: Bundle = .main) -> DropboxConfig? {
        guard let url = bundle.url(forResource: "Config", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let key = (dict["DropboxAppKey"] as? String)?.trimmingCharacters(in: .whitespaces),
              !key.isEmpty, !key.hasPrefix("YOUR_")
        else { return nil }
        let access = AccessType(rawValue: dict["DropboxAccessType"] as? String ?? "") ?? .appFolder
        let folder = (dict["DropboxFolderPath"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return DropboxConfig(appKey: key, accessType: access, folderOverride: folder)
    }
}

enum DropboxPath {
    /// "" (root) or "/a/b" with no trailing slash.
    static func normalize(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/ ").union(.whitespaces))
        return trimmed.isEmpty ? "" : "/" + trimmed
    }

    static func join(_ folder: String, _ name: String) -> String {
        normalize(folder) + "/" + name
    }

    static func displayName(_ folder: String) -> String {
        let n = normalize(folder)
        return n.isEmpty ? "/" : n
    }
}
