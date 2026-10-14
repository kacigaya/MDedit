import Foundation
import UniformTypeIdentifiers

/// What following a link may do. A document can come from anywhere, and its
/// link text need not match where the link goes, so ⌘-click must not run
/// programs or hand arbitrary URL schemes to other apps unasked.
enum LinkPolicy {
    enum Action: Equatable {
        /// Safe to open straight away.
        case open
        /// Opens only after the user agrees, having seen the address.
        case confirm
        /// Shown in Finder, never opened: it would run something.
        case reveal
    }

    /// Web pages and mail open; any other scheme asks first.
    static let trustedSchemes: Set<String> = ["http", "https", "mailto"]

    static func action(forScheme scheme: String) -> Action {
        trustedSchemes.contains(scheme.lowercased()) ? .open : .confirm
    }

    /// Files that launch, install or script something when opened.
    static let runnableExtensions: Set<String> = [
        "app", "command", "tool", "terminal", "sh", "bash", "zsh", "csh", "ksh", "fish", "py", "pl", "rb",
        "scpt", "scptd", "applescript", "workflow", "action", "shortcut", "jar", "pkg", "mpkg",
        "prefpane", "saver", "qlgenerator", "plugin", "kext", "mobileconfig", "dmg",
        "inetloc", "webloc", "fileloc", "url", "terminalsettings",
    ]

    static func action(forFile link: URL) -> Action {
        // Judged by what opening it reaches: a harmless name can be a
        // symlink to something that runs.
        let url = link.resolvingSymlinksInPath()
        if runnableExtensions.contains(link.pathExtension.lowercased()) || runnableExtensions.contains(url.pathExtension.lowercased()) {
            return .reveal
        }
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
        if let type = values?.contentType,
           [.executable, .application, .applicationBundle, .script, .shellScript].contains(where: type.conforms(to:)) {
            return .reveal
        }
        // An extensionless file with the execute bit runs in Terminal.
        if values?.isDirectory != true, FileManager.default.isExecutableFile(atPath: url.path) { return .reveal }
        return .open
    }
}
