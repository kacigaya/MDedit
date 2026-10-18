import Foundation

/// Watches one file for changes made outside the app.
///
/// Editors that rewrite a file replace it rather than writing in place, so a
/// rename or delete is treated as a change and the watch is re-established.
/// `@unchecked Sendable` because every member is created and touched on the
/// main queue, which is also the queue the dispatch source fires on.
final class FileWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private let url: URL
    private let onChange: @MainActor () -> Void

    init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
        guard start() else { return nil }
    }

    deinit {
        source?.cancel()
    }

    @discardableResult
    private func start() -> Bool {
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            // The source fires on the main queue, so this is already isolated.
            MainActor.assumeIsolated {
                guard let self else { return }
                let events = source.data
                self.onChange()
                if events.contains(.delete) || events.contains(.rename) {
                    // The file was replaced; follow it to the new inode.
                    self.restart()
                }
            }
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source
        return true
    }

    @MainActor
    private func restart(attempt: Int = 0) {
        source?.cancel()
        source = nil
        descriptor = -1
        // Give the replacing writer a moment to finish, and keep looking for
        // a while: a checkout or a sync can leave the path empty for longer,
        // and a watch given up on misses every later change unnoticed.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.source == nil else { return }
                if self.start() {
                    // Back, perhaps after the change was looked at and the
                    // file found missing: what it holds now is news too.
                    self.onChange()
                } else if attempt + 1 < Self.retries {
                    self.restart(attempt: attempt + 1)
                }
            }
        }
    }

    private static let retryDelay = 0.1
    /// Two seconds of looking, after which the document is marked missing
    /// on disk and saving it watches again.
    private static let retries = 20
}
