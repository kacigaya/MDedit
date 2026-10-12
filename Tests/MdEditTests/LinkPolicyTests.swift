import Foundation
import Testing
@testable import MdEdit

@Suite("Link policy")
struct LinkPolicyTests {
    private func temporaryFile(_ name: String, executable: Bool = false) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MdEditLinks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try "echo hi".write(to: file, atomically: true, encoding: .utf8)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }
        return file
    }

    @Test("Web and mail links open; other schemes ask first")
    func schemes() {
        #expect(LinkPolicy.action(forScheme: "https") == .open)
        #expect(LinkPolicy.action(forScheme: "HTTP") == .open)
        #expect(LinkPolicy.action(forScheme: "mailto") == .open)
        #expect(LinkPolicy.action(forScheme: "smb") == .confirm)
        #expect(LinkPolicy.action(forScheme: "x-apple.systempreferences") == .confirm)
        #expect(LinkPolicy.action(forScheme: "javascript") == .confirm)
    }

    @Test("Programs and scripts are revealed, documents open")
    func files() throws {
        #expect(LinkPolicy.action(forFile: try temporaryFile("setup.command")) == .reveal)
        #expect(LinkPolicy.action(forFile: try temporaryFile("run.sh")) == .reveal)
        #expect(LinkPolicy.action(forFile: try temporaryFile("Tool.app")) == .reveal)
        #expect(LinkPolicy.action(forFile: try temporaryFile("install", executable: true)) == .reveal)
        #expect(LinkPolicy.action(forFile: try temporaryFile("notes.txt")) == .open)
        #expect(LinkPolicy.action(forFile: try temporaryFile("paper.pdf")) == .open)
    }

    @Test("Update links only ever go to GitHub")
    func releasePage() {
        #expect(UpdateChecker.isReleasePage(URL(string: "https://github.com/msk-mdi/MDedit/releases/tag/v1.0")!))
        #expect(!UpdateChecker.isReleasePage(URL(string: "https://evil.example/MdEdit.dmg")!))
        #expect(!UpdateChecker.isReleasePage(URL(string: "file:///Applications/Calculator.app")!))
    }
}
