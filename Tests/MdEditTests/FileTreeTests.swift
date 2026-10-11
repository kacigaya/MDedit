import AppKit
import Testing
@testable import MdEdit

@MainActor
@Suite("File tree")
struct FileTreeTests {
    /// A folder with `notes/` holding one file, and `top.md` beside it.
    private func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MdEditTree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("top.md"))
        try Data().write(to: root.appendingPathComponent("notes/first.md"))
        return root
    }

    /// The tree in a window, as the sidebar shows it.
    private func makeTree(_ root: URL) -> (FileTreeView, NSWindow) {
        let tree = FileTreeView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = tree
        tree.setRoot(root)
        return (tree, window)
    }

    private func rows(_ tree: FileTreeView) -> [String] {
        (0..<tree.outline.numberOfRows).compactMap { (tree.outline.item(atRow: $0) as? FileNode)?.url.lastPathComponent }
    }

    /// FSEvents names folders with symlinks resolved; the temporary folder is
    /// under one, /var to /private/var.
    private func reported(_ url: URL) -> String {
        realPath(url.path) + "/"
    }

    @Test("A change re-lists only that folder, keeping what is open and selected")
    func refreshKeepsState() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (tree, window) = makeTree(root)
        _ = window
        let notes = try #require(tree.outline.item(atRow: 0) as? FileNode)
        tree.outline.expandItem(notes)
        tree.reveal(root.appendingPathComponent("notes/first.md"))
        #expect(rows(tree) == ["notes", "first.md", "top.md"])

        try Data().write(to: root.appendingPathComponent("notes/second.md"))
        tree.folderContentsChanged(.folders([reported(root.appendingPathComponent("notes"))]))
        #expect(rows(tree) == ["notes", "first.md", "second.md", "top.md"])
        #expect(tree.outline.item(atRow: 0) as? FileNode === notes)
        #expect(tree.outline.isItemExpanded(notes))
        #expect((tree.outline.item(atRow: tree.outline.selectedRow) as? FileNode)?.url.lastPathComponent == "first.md")

        // The root itself, with a folder that is open below it.
        try Data().write(to: root.appendingPathComponent("another.md"))
        tree.folderContentsChanged(.folders([reported(root)]))
        #expect(rows(tree) == ["notes", "first.md", "second.md", "another.md", "top.md"])
        #expect(tree.outline.isItemExpanded(notes))
    }

    @Test("Changes in hidden and dependency folders, or folders never listed, read nothing")
    func ignoredFolders() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (tree, window) = makeTree(root)
        _ = window
        #expect(rows(tree) == ["notes", "top.md"])
        let notes = try #require(tree.outline.item(atRow: 0) as? FileNode)

        try Data().write(to: root.appendingPathComponent("unseen.md"))
        for folder in [".git", ".git/objects", "node_modules/pkg", "notes"] {
            tree.folderContentsChanged(.folders([reported(root) + folder]))
        }
        // The root was not read again, and `notes`, never opened, was not listed.
        #expect(rows(tree) == ["notes", "top.md"])
        #expect(notes.listedChildren == nil)
    }

    @Test("Out of sight, the tree waits until it is shown")
    func hiddenTreeDefers() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (tree, window) = makeTree(root)
        _ = window
        tree.isHidden = true
        try Data().write(to: root.appendingPathComponent("later.md"))
        tree.folderContentsChanged(.folders([reported(root)]))
        #expect(rows(tree) == ["notes", "top.md"])

        tree.isHidden = false
        #expect(rows(tree) == ["notes", "later.md", "top.md"])
    }

    @Test("The watcher reports the folder a file changed in")
    func watcherReportsFolders() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        final class Box { var folders: [String] = [] }
        let box = Box()
        let watcher = DirectoryWatcher(url: root) { change in
            if case let .folders(folders) = change { box.folders += folders }
        }
        #expect(watcher != nil)
        // FSEvents starts watching a moment after the stream does.
        try await Task.sleep(for: .milliseconds(300))
        try Data().write(to: root.appendingPathComponent("notes/new.md"))
        for _ in 0..<50 where box.folders.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        let notes = realPath(root.appendingPathComponent("notes").path)
        #expect(box.folders.contains { $0 == notes || $0 == notes + "/" }, "\(box.folders)")
        withExtendedLifetime(watcher) {}
    }
}
