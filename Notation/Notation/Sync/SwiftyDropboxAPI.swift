import Foundation
import SwiftyDropbox

/// `DropboxAPI` on top of the official Dropbox Swift SDK. This is the only file that touches SwiftyDropbox
/// (auth is handled separately by `DropboxAuth`, which feeds this client a fresh access token).
struct SwiftyDropboxAPI: DropboxAPI {
    let client: DropboxClient

    init(accessToken: String) {
        client = DropboxClient(accessToken: accessToken)
    }

    func listFiles(in folder: String) async throws -> [RemoteFile] {
        let path = DropboxPath.normalize(folder)
        var files: [RemoteFile] = []
        do {
            var page = try await client.files.listFolder(path: path).response()
            while true {
                files += page.entries.compactMap { entry in
                    (entry as? Files.FileMetadata).map { RemoteFile(name: $0.name, rev: $0.rev, serverModified: $0.serverModified) }
                }
                guard page.hasMore else { break }
                page = try await client.files.listFolderContinue(cursor: page.cursor).response()
            }
        } catch {
            guard Self.isNotFound(error), !path.isEmpty else { throw error }
            _ = try await client.files.createFolderV2(path: path).response()
            return []
        }
        return files
    }

    func download(_ name: String, in folder: String) async throws -> RemoteContent {
        let result = try await client.files.download(path: DropboxPath.join(folder, name)).response()
        let metadata = result.0
        let data = result.1
        return RemoteContent(body: String(decoding: data, as: UTF8.self), rev: metadata.rev, serverModified: metadata.serverModified)
    }

    func upload(_ body: String, name: String, in folder: String, replacing rev: String?) async throws -> RemoteFile {
        let mode: Files.WriteMode = rev.map { .update($0) } ?? .add
        let metadata = try await client.files.upload(
            path: DropboxPath.join(folder, name),
            mode: mode,
            autorename: false,
            input: Data(body.utf8)
        ).response()
        return RemoteFile(name: metadata.name, rev: metadata.rev, serverModified: metadata.serverModified)
    }

    func delete(_ name: String, in folder: String) async throws {
        do {
            _ = try await client.files.deleteV2(path: DropboxPath.join(folder, name)).response()
        } catch {
            if !Self.isNotFound(error) { throw error }
        }
    }

    func listFolders(in path: String) async throws -> [String] {
        let normalized = DropboxPath.normalize(path)
        var names: [String] = []
        var page = try await client.files.listFolder(path: normalized).response()
        while true {
            names += page.entries.compactMap { ($0 as? Files.FolderMetadata)?.name }
            guard page.hasMore else { break }
            page = try await client.files.listFolderContinue(cursor: page.cursor).response()
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The SDK's route errors are nested enums; matching on their description keeps this independent of the exact shape.
    private static func isNotFound(_ error: Error) -> Bool {
        let text = String(describing: error).lowercased()
        return text.contains("not_found") || text.contains("notfound")
    }
}
