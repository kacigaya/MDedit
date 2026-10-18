import Foundation

/// Bookmarks to the files and folders the user opened, so the next launch
/// can reach them again.
///
/// Sandboxed, a path alone grants nothing once the app quits: reopening the
/// session, a workspace folder or a file takes a security-scoped bookmark
/// made while access was granted. Unsandboxed, a bookmark still follows a
/// file renamed or moved between launches.
enum FileAccess {
    private static let defaultsKey = "fileBookmarks"
    private static let pinnedKey = "pinnedFileBookmarks"
    /// Enough for every tab and folder of a session, with room to spare.
    static let limit = 300

    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private static var options: (create: URL.BookmarkCreationOptions, resolve: URL.BookmarkResolutionOptions) {
        // Without mounting: a bookmark to a server or disk no longer there
        // tried to mount it, holding up launch until that gave up.
        isSandboxed
            ? (.withSecurityScope, [.withSecurityScope, .withoutUI, .withoutMounting])
            : ([], [.withoutUI, .withoutMounting])
    }

    /// Records a bookmark for a file or folder the app can reach right now.
    static func remember(_ url: URL, in defaults: UserDefaults = .standard) {
        guard url.isFileURL, let data = try? url.bookmarkData(options: options.create) else { return }
        var bookmarks = load(from: defaults)
        bookmarks.removeAll { $0.path == url.standardizedFileURL.path }
        bookmarks.append(Entry(path: url.standardizedFileURL.path, data: data))
        // The oldest go first, except those the session still needs: losing
        // the workspace folder's would lose the folder, sandboxed.
        let pinned = Set(defaults.stringArray(forKey: pinnedKey) ?? [])
        var excess = bookmarks.count - limit
        if excess > 0 {
            bookmarks.removeAll { entry in
                guard excess > 0, !pinned.contains(entry.path) else { return false }
                excess -= 1
                return true
            }
        }
        save(bookmarks, to: defaults)
    }

    /// Keeps the bookmarks of these files and folders, the open session's,
    /// however many others are remembered after them.
    static func pin(_ urls: [URL], in defaults: UserDefaults = .standard) {
        defaults.set(urls.map(\.standardizedFileURL.path), forKey: pinnedKey)
    }

    /// Where a remembered file is now, with access to it started. A file
    /// with no bookmark, or one that no longer resolves, comes back as given.
    static func resolve(_ url: URL, in defaults: UserDefaults = .standard) -> URL {
        resolve([url], in: defaults)[0]
    }

    /// Several at once, as a session's tabs are: each one read and decoded
    /// the whole list of bookmarks again.
    static func resolve(_ urls: [URL], in defaults: UserDefaults = .standard) -> [URL] {
        guard !urls.isEmpty else { return [] }
        var byPath: [String: Data] = [:]
        for entry in load(from: defaults) { byPath[entry.path] = entry.data }
        var moved: [URL] = []
        let resolved = urls.map { url -> URL in
            let path = url.standardizedFileURL.path
            guard let data = byPath[path] else { return url }
            var isStale = false
            guard let resolved = try? URL(resolvingBookmarkData: data, options: options.resolve, bookmarkDataIsStale: &isStale) else {
                return url
            }
            // Held for the rest of the run: the tab or folder stays open.
            if isSandboxed { _ = resolved.startAccessingSecurityScopedResource() }
            if isStale || resolved.standardizedFileURL.path != path { moved.append(resolved) }
            return resolved
        }
        for url in moved { remember(url, in: defaults) }
        return resolved
    }

    private struct Entry: Codable {
        var path: String
        var data: Data
    }

    private static func load(from defaults: UserDefaults) -> [Entry] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        return (try? PropertyListDecoder().decode([Entry].self, from: data)) ?? []
    }

    private static func save(_ bookmarks: [Entry], to defaults: UserDefaults) {
        if let data = try? PropertyListEncoder().encode(bookmarks) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
