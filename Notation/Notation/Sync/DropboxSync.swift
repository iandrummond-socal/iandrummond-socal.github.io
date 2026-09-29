import Foundation
import Network
import Observation

/// Owns Dropbox state for the UI: connect/disconnect, when to sync, and reachability.
/// Local editing never waits on this; when offline or disconnected, edits just stay queued as unsynced.
@MainActor
@Observable
final class DropboxSync {
    private(set) var isConnected = false
    private(set) var isSyncing = false
    private(set) var isOnline = true
    private(set) var lastError: String?

    let config: DropboxConfig?
    /// Called after every pass so the notebook can refresh its list and show a conflict notice.
    @ObservationIgnored var onFinished: ((SyncSummary) -> Void)?

    @ObservationIgnored private let store: NoteStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let auth: DropboxAuth?
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var resyncAfterCurrent = false

    var isConfigured: Bool { config != nil }

    init(store: NoteStore, settings: AppSettings, config: DropboxConfig?) {
        self.store = store
        self.settings = settings
        self.config = config
        self.auth = config.map(DropboxAuth.init(config:))
        self.isConnected = auth?.hasCredentials ?? false

        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.reachabilityChanged(online) }
        }
        monitor.start(queue: DispatchQueue(label: "notation.reachability"))
    }

    // MARK: - Account

    func connect() async {
        guard let auth else {
            lastError = "Add your Dropbox app key to Config.plist (see README)."
            return
        }
        do {
            try await auth.connect()
            isConnected = true
            lastError = nil
            await syncNow()
        } catch AuthError.cancelled {
            // User backed out; nothing to report.
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        auth?.disconnect()
        isConnected = false
        scheduled?.cancel()
        store.resetSyncState()
    }

    /// Points sync at another Dropbox folder. Local notes are treated as unsynced and reconciled by name.
    func changeFolder(to path: String) async {
        settings.dropboxFolder = DropboxPath.normalize(path)
        store.resetSyncState()
        await syncNow()
    }

    /// Subfolders of `path`, for the folder chooser.
    func folders(in path: String) async throws -> [String] {
        guard let api = try await makeAPI() else { throw AuthError.notConnected }
        return try await api.listFolders(in: path)
    }

    // MARK: - Syncing

    func syncNow() async {
        guard isConnected else { return }
        guard !isSyncing else {
            resyncAfterCurrent = true
            return
        }
        guard isOnline else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            guard let api = try await makeAPI() else { return }
            let engine = SyncEngine(api: api, store: store, folder: settings.dropboxFolder)
            let summary = try await engine.run()
            settings.lastSync = Date()
            lastError = summary.errors.first
            onFinished?(summary)
        } catch AuthError.notConnected {
            isConnected = false
            lastError = "Dropbox session expired. Reconnect in Settings."
        } catch {
            lastError = error.localizedDescription
        }

        if resyncAfterCurrent {
            resyncAfterCurrent = false
            schedule(after: 2)
        }
    }

    /// Debounced: edits arriving in a burst produce one pass.
    func schedule(after seconds: TimeInterval) {
        guard isConnected else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    private func makeAPI() async throws -> DropboxAPI? {
        guard let auth else { return nil }
        let token = try await auth.validAccessToken()
        return SwiftyDropboxAPI(accessToken: token)
    }

    private func reachabilityChanged(_ online: Bool) {
        let cameBack = online && !isOnline
        isOnline = online
        if cameBack { schedule(after: 1) }
    }
}
