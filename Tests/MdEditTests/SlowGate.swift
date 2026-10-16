import Foundation
import Testing

/// Stands in for a disk slow to answer: each read waits at the gate until
/// the test opens it, and notes the thread it ran on. A read made on the
/// main thread holds the test up so that it cannot open the gate, which
/// then gives up after a while and says so.
final class SlowGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var isOpen = false
    private var threads: [Bool] = []
    private var didGiveUp = false

    /// Called from a read; returns once the gate is open.
    func pass() {
        condition.lock()
        defer { condition.unlock() }
        threads.append(Thread.isMainThread)
        // Generous: on a busy CI runner, other suites' tests can hold the
        // main actor for many seconds before this one gets to open the gate.
        let deadline = Date(timeIntervalSinceNow: 60)
        while !isOpen {
            if !condition.wait(until: deadline) {
                didGiveUp = true
                return
            }
        }
    }

    func open() {
        condition.lock()
        isOpen = true
        condition.broadcast()
        condition.unlock()
    }

    var calls: Int { condition.withLock { threads.count } }
    var ranOnMainThread: Bool { condition.withLock { threads.contains(true) } }
    /// A read waited the whole while: something kept the gate from being opened.
    var gaveUp: Bool { condition.withLock { didGiveUp } }

    /// Waits, with the main actor free, until reads are held at the gate.
    @MainActor
    func waitForReads(_ count: Int = 1) async throws {
        for _ in 0..<3000 where calls < count {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(calls >= count)
    }
}
