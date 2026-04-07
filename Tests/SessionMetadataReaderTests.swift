//
//  SessionMetadataReaderTests.swift
//
//  Tests for the reader that pulls Claude Code's /resume title from
//  ~/.claude/sessions/<pid>.json. Uses a temp directory of fixture files
//  so we don't depend on the real ~/.claude/sessions/ state.
//

import Foundation

@main
struct SessionMetadataReaderTests {
    /// Writes a single `<pid>.json` fixture into a temp directory.
    static func writeFixture(
        pid: Int,
        sessionId: String,
        name: String?,
        to dir: URL
    ) {
        var json: [String: Any] = [
            "pid": pid,
            "sessionId": sessionId,
            "cwd": "/tmp/fake",
            "startedAt": 1775513659851,
            "kind": "interactive",
            "entrypoint": "cli"
        ]
        if let name = name {
            json["name"] = name
        }
        let data = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        let url = dir.appendingPathComponent("\(pid).json")
        try! data.write(to: url)
    }

    /// Creates a fresh temp directory and returns it. Caller must clean up.
    static func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-island-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func main() {
        test("decode parses a well-formed metadata file") {
            let json = #"{"pid":45365,"sessionId":"abc","cwd":"/tmp","startedAt":1,"kind":"interactive","entrypoint":"cli","name":"reposition-overlay-top-right"}"#
            let meta = SessionMetadataReader.decode(json.data(using: .utf8)!)
            assertTrue(meta != nil, "decode should succeed")
            assertEqual(meta!.pid, 45365, "pid")
            assertEqual(meta!.sessionId, "abc", "sessionId")
            assertEqual(meta!.name, "reposition-overlay-top-right", "name")
        }

        test("decode returns nil for a file missing required fields") {
            let json = #"{"kind":"interactive","entrypoint":"cli"}"#
            let meta = SessionMetadataReader.decode(json.data(using: .utf8)!)
            assertTrue(meta == nil, "decode should fail on missing pid/sessionId")
        }

        test("decode returns nil-name when name is missing") {
            let json = #"{"pid":1686,"sessionId":"xyz","cwd":"/tmp","startedAt":1,"kind":"interactive","entrypoint":"cli"}"#
            let meta = SessionMetadataReader.decode(json.data(using: .utf8)!)
            assertTrue(meta != nil, "decode should still succeed without name")
            assertTrue(meta!.name == nil, "name should be nil when absent")
        }

        test("decode treats empty-string name as nil") {
            let json = #"{"pid":1,"sessionId":"x","name":""}"#
            let meta = SessionMetadataReader.decode(json.data(using: .utf8)!)
            assertTrue(meta != nil, "decode succeeds")
            assertTrue(meta!.name == nil, "empty name collapses to nil")
        }

        test("decode treats whitespace-only name as nil") {
            let json = #"{"pid":1,"sessionId":"x","name":"   \n"}"#
            let meta = SessionMetadataReader.decode(json.data(using: .utf8)!)
            assertTrue(meta != nil, "decode succeeds")
            assertTrue(meta!.name == nil, "whitespace name collapses to nil")
        }

        test("findName returns the name for a matching sessionId") {
            let dir = makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            writeFixture(pid: 1686, sessionId: "session-a", name: nil, to: dir)
            writeFixture(pid: 45365, sessionId: "session-b", name: "reposition-overlay-top-right", to: dir)
            writeFixture(pid: 55818, sessionId: "session-c", name: nil, to: dir)

            let found = SessionMetadataReader.findName(for: "session-b", in: dir)
            assertEqual(found, "reposition-overlay-top-right", "matching session returns its name")
        }

        test("findName returns nil when the sessionId isn't present") {
            let dir = makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            writeFixture(pid: 1, sessionId: "session-a", name: "alpha", to: dir)
            writeFixture(pid: 2, sessionId: "session-b", name: "beta", to: dir)

            let found = SessionMetadataReader.findName(for: "session-z", in: dir)
            assertTrue(found == nil, "missing session returns nil")
        }

        test("findName returns nil when the matching session has no name yet") {
            let dir = makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            writeFixture(pid: 1686, sessionId: "session-a", name: nil, to: dir)
            let found = SessionMetadataReader.findName(for: "session-a", in: dir)
            assertTrue(found == nil, "matching session with no name returns nil")
        }

        test("findName returns nil when the directory doesn't exist") {
            let nonexistent = FileManager.default.temporaryDirectory
                .appendingPathComponent("nope-\(UUID().uuidString)")
            let found = SessionMetadataReader.findName(for: "session-a", in: nonexistent)
            assertTrue(found == nil, "missing directory returns nil (no crash)")
        }

        test("findName ignores non-json files in the directory") {
            let dir = makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            // Drop a text file that shouldn't parse as json
            try! "not json".write(
                to: dir.appendingPathComponent("readme.txt"),
                atomically: true,
                encoding: .utf8
            )
            writeFixture(pid: 1, sessionId: "session-a", name: "found-me", to: dir)

            let found = SessionMetadataReader.findName(for: "session-a", in: dir)
            assertEqual(found, "found-me", "ignores non-json and still finds match")
        }

        test("findMetadata returns full record, not just name") {
            let dir = makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            writeFixture(pid: 99999, sessionId: "full-record", name: "hello", to: dir)
            let meta = SessionMetadataReader.findMetadata(for: "full-record", in: dir)
            assertTrue(meta != nil, "metadata should be found")
            assertEqual(meta!.pid, 99999, "pid on full record")
            assertEqual(meta!.sessionId, "full-record", "sessionId on full record")
            assertEqual(meta!.name, "hello", "name on full record")
        }

        finish("SessionMetadataReaderTests")
    }
}
