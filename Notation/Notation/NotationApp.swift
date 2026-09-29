import SwiftUI

@main
struct NotationApp: App {
    @State private var model: NotebookModel
    @State private var sync: DropboxSync
    @State private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let config = DropboxConfig.load()
        let settings = AppSettings(defaultFolder: config?.defaultFolder ?? "")
        let store = NoteStore()
        store.load()
        let sync = DropboxSync(store: store, settings: settings, config: config)
        let model = NotebookModel(store: store, settings: settings)
        model.onLocalChange = { [weak sync] delay in sync?.schedule(after: delay) }
        sync.onFinished = { [weak model] summary in model?.syncFinished(summary) }

        _settings = State(initialValue: settings)
        _sync = State(initialValue: sync)
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            NotebookView(model: model, sync: sync, settings: settings)
                .task { await sync.syncNow() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await sync.syncNow() }
            case .background, .inactive:
                model.flushSave()
            @unknown default:
                break
            }
        }
    }
}
