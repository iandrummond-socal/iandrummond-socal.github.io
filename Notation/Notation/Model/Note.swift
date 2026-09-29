import Foundation

/// One note = one `.txt` file. The filename is the storage key; the title is the filename without `.txt`.
struct Note: Identifiable, Equatable {
    var filename: String {
        didSet { refreshTitle() }
    }
    var body: String {
        didSet { lowerBody = body.lowercased() }
    }
    var modified: Date
    /// Dropbox revision this copy was last in sync with. `nil` = never synced.
    var rev: String?
    /// Local content differs from the last synced copy (upload pending).
    var dirty: Bool
    /// Bumped on every local content change, so sync can tell if a note changed while it was awaiting the network.
    var version: Int = 0

    private(set) var title: String
    private(set) var lowerTitle: String
    private(set) var lowerBody: String

    var id: String { filename }
    var key: String { filename.lowercased() }

    init(filename: String, body: String, modified: Date, rev: String? = nil, dirty: Bool = false) {
        self.filename = filename
        self.body = body
        self.modified = modified
        self.rev = rev
        self.dirty = dirty
        let t = FilenameRules.title(fromFilename: filename)
        self.title = t
        self.lowerTitle = t.lowercased()
        self.lowerBody = body.lowercased()
    }

    private mutating func refreshTitle() {
        title = FilenameRules.title(fromFilename: filename)
        lowerTitle = title.lowercased()
    }
}

enum FilenameRules {
    static let maxTitleLength = 120
    static let fileExtension = "txt"

    /// Characters that are path separators or that Dropbox / common file systems reject.
    private static let forbidden = CharacterSet(charactersIn: "/\\:<>\"|?*").union(.controlCharacters)

    /// Turns whatever the user typed into a human title that is safe as a filename stem, or `nil` if nothing is left.
    /// Strips path separators and reserved characters, collapses whitespace, drops leading dots, caps at 120 characters.
    static func cleanTitle(_ raw: String) -> String? {
        let kept = raw.unicodeScalars.filter { $0.properties.isWhitespace || !forbidden.contains($0) }
        var s = String(String.UnicodeScalarView(kept))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        while s.hasPrefix(".") || s.hasPrefix(" ") { s.removeFirst() }
        if s.count > maxTitleLength { s = String(s.prefix(maxTitleLength)) }
        while s.hasSuffix(".") || s.hasSuffix(" ") { s.removeLast() }
        return s.isEmpty ? nil : s
    }

    static func filename(forTitle raw: String) -> String? {
        cleanTitle(raw).map { $0 + "." + fileExtension }
    }

    static func title(fromFilename name: String) -> String {
        let suffix = "." + fileExtension
        if name.lowercased().hasSuffix(suffix) { return String(name.dropLast(suffix.count)) }
        return name
    }

    /// v1 only handles visible `.txt` files, and skips Dropbox's own "conflicted copy" files.
    static func isNoteFilename(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard !name.hasPrefix("."), lower.hasSuffix("." + fileExtension) else { return false }
        if lower.contains("conflicted copy") { return false }
        return true
    }
}
