import SwiftUI

/// Reached from the small gear next to the field. Not a tab.
struct SettingsView: View {
    let sync: DropboxSync
    @Bindable var settings: AppSettings
    let onSortChanged: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                dropboxSection
                if sync.isConnected { syncSection }
                displaySection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.text)
    }

    private var dropboxSection: some View {
        Section {
            if !sync.isConfigured {
                Text("Add your Dropbox app key to Config.plist to enable sync. Notes work without it and are stored on this device.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            } else if sync.isConnected {
                LabeledContent("Folder", value: DropboxPath.displayName(settings.dropboxFolder))
                NavigationLink("Change folder") {
                    FolderPicker(sync: sync, settings: settings)
                }
                Button("Disconnect Dropbox", role: .destructive) { sync.disconnect() }
            } else {
                Button("Connect Dropbox") { Task { await sync.connect() } }
            }
            if let error = sync.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
        } header: {
            Text("Dropbox")
        }
        .listRowBackground(Theme.field)
    }

    private var syncSection: some View {
        Section {
            LabeledContent("Last sync", value: lastSyncText)
            Button {
                Task { await sync.syncNow() }
            } label: {
                HStack {
                    Text("Sync now")
                    if sync.isSyncing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(sync.isSyncing || !sync.isOnline)
            if !sync.isOnline {
                Text("Offline. Edits are saved here and will upload when you’re back online.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
        } header: {
            Text("Sync")
        }
        .listRowBackground(Theme.field)
    }

    private var displaySection: some View {
        Section {
            Picker("Sort", selection: $settings.sortMode) {
                ForEach(SortMode.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: settings.sortMode) { _, _ in onSortChanged() }
            Stepper(value: $settings.fontSize, in: AppSettings.fontSizeRange, step: 1) {
                Text("Font size: \(Int(settings.fontSize)) pt")
            }
        } header: {
            Text("Display")
        }
        .listRowBackground(Theme.field)
    }

    private var lastSyncText: String {
        guard let date = settings.lastSync else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Browses Dropbox folders and picks one to hold the notes.
struct FolderPicker: View {
    let sync: DropboxSync
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var path: String
    @State private var folders: [String] = []
    @State private var loading = false
    @State private var errorText: String?

    init(sync: DropboxSync, settings: AppSettings) {
        self.sync = sync
        self.settings = settings
        _path = State(initialValue: settings.dropboxFolder)
    }

    var body: some View {
        List {
            Section {
                Button("Use “\(DropboxPath.displayName(path))”") {
                    Task {
                        await sync.changeFolder(to: path)
                        dismiss()
                    }
                }
            } footer: {
                Text("Notes are stored as .txt files in this folder.")
            }
            .listRowBackground(Theme.field)

            Section {
                if !path.isEmpty {
                    Button("Up one level") { path = parent(of: path) }
                }
                ForEach(folders, id: \.self) { name in
                    Button(name) { path = DropboxPath.join(path, name) }
                }
                if loading {
                    ProgressView()
                } else if folders.isEmpty, errorText == nil {
                    Text("No subfolders").foregroundStyle(Theme.secondary)
                }
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
            .listRowBackground(Theme.field)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Folder")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: path) { await load() }
    }

    private func load() async {
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            folders = try await sync.folders(in: path)
        } catch {
            folders = []
            // A folder that doesn't exist yet (e.g. the default) is fine; it is created on first sync.
            errorText = path == settings.dropboxFolder ? nil : error.localizedDescription
        }
    }

    private func parent(of path: String) -> String {
        let parts = DropboxPath.normalize(path).split(separator: "/").dropLast()
        return parts.isEmpty ? "" : "/" + parts.joined(separator: "/")
    }
}
