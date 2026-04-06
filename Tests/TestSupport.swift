//
//  TestSupport.swift
//  Claude Island standalone test runner
//
//  Tiny assertion helpers used by every test file. No XCTest dependency.
//  Each test file imports this implicitly by being compiled alongside it.
//

import Foundation

/// Counter for passing assertions, used for the final summary line.
nonisolated(unsafe) var passedAssertions: Int = 0

func assertTrue(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #file,
    line: UInt = #line
) {
    if !condition() {
        fail("expected true: \(message)", file: file, line: line)
    }
    passedAssertions += 1
}

func assertEqual<T: Equatable>(
    _ actual: @autoclosure () -> T,
    _ expected: @autoclosure () -> T,
    _ message: String,
    file: StaticString = #file,
    line: UInt = #line
) {
    let a = actual()
    let e = expected()
    if a != e {
        fail("\(message) — expected \(e), got \(a)", file: file, line: line)
    }
    passedAssertions += 1
}

/// Approximate equality for floating point comparisons.
func assertEqual(
    _ actual: @autoclosure () -> CGFloat,
    _ expected: @autoclosure () -> CGFloat,
    accuracy: CGFloat = 0.001,
    _ message: String,
    file: StaticString = #file,
    line: UInt = #line
) {
    let a = actual()
    let e = expected()
    if abs(a - e) > accuracy {
        fail("\(message) — expected \(e) ± \(accuracy), got \(a)", file: file, line: line)
    }
    passedAssertions += 1
}

func fail(_ message: String, file: StaticString = #file, line: UInt = #line) -> Never {
    let filename = "\(file)".split(separator: "/").last ?? "?"
    fputs("\u{001B}[31mFAIL\u{001B}[0m \(filename):\(line) — \(message)\n", stderr)
    exit(1)
}

/// Run a named test block. Prints a check on success.
func test(_ name: String, _ block: () -> Void) {
    block()
    print("\u{001B}[32m✓\u{001B}[0m \(name)")
}

/// Print the suite summary and exit 0. Call at the end of a test executable.
func finish(_ suiteName: String) -> Never {
    print("\u{001B}[32m\(suiteName) — \(passedAssertions) assertion(s) passed\u{001B}[0m")
    exit(0)
}
