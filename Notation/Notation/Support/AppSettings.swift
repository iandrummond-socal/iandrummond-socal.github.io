import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let fontSizeRange: ClosedRange<Double> = 12...28

    @ObservationIgnored private let defaults: UserDefaults

    var sortMode: SortMode {
        didSet { defaults.set(sortMode.rawValue, forKey: "sortMode") }
    }
    var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: "fontSize") }
    }
    /// Dropbox folder that mirrors the local notes ("" = root of an app-folder app).
    var dropboxFolder: String {
        didSet { defaults.set(dropboxFolder, forKey: "dropboxFolder") }
    }
    var lastSync: Date? {
        didSet { defaults.set(lastSync, forKey: "lastSync") }
    }

    init(defaults: UserDefaults = .standard, defaultFolder: String = "") {
        self.defaults = defaults
        sortMode = SortMode(rawValue: defaults.string(forKey: "sortMode") ?? "") ?? .modified
        let size = defaults.double(forKey: "fontSize")
        fontSize = size == 0 ? 17 : min(max(size, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        dropboxFolder = defaults.string(forKey: "dropboxFolder") ?? defaultFolder
        lastSync = defaults.object(forKey: "lastSync") as? Date
    }
}
