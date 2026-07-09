// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-foundations open source project
//
// Copyright (c) 2024-2025 Coen ten Thije Boonkkamp and the swift-foundations
// project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import Testing

@testable import Witnesses

extension Source.Location {
    @Suite("Source.Location")
    struct Test {
        @Suite struct Unit {}
        @Suite struct EdgeCase {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit Tests

extension Source.Location.Test.Unit {
    @Test
    func `Location stores fileID, filePath, line, and column`() {
        let location = Source.Location(
            fileID: "Test.swift",
            filePath: "/path/Test.swift",
            line: 42,
            column: 7
        )

        #expect(location.fileID == "Test.swift")
        #expect(location.filePath == "/path/Test.swift")
        #expect(location.line == 42)
        #expect(location.column == 7)
    }

    @Test
    func `Location uses default values from call site`() {
        let location = Source.Location(
            fileID: #fileID,
            filePath: #filePath,
            line: #line,
            column: #column
        )

        #expect(location.fileID.contains("Unimplemented.Location Tests"))
        #expect(location.line > 0)
        #expect(location.column > 0)
    }

    @Test
    func `Location is Sendable`() async {
        let location = Source.Location(
            fileID: "Test.swift",
            line: 42,
            column: 7
        )

        await Task {
            #expect(location.fileID == "Test.swift")
            #expect(location.line == 42)
        }.value
    }
}

// MARK: - Edge Case Tests

extension Source.Location.Test.EdgeCase {
    @Test
    func `Location with empty fileID`() {
        let location = Source.Location(
            fileID: "",
            line: 1,
            column: 1
        )
        #expect(location.fileID.isEmpty)
    }

    @Test
    func `Location with zero line`() {
        let location = Source.Location(
            fileID: "Test.swift",
            line: 0,
            column: 1
        )
        #expect(location.line == 0)
    }

    @Test
    func `Location with large line number`() {
        let location = Source.Location(
            fileID: "Test.swift",
            line: Int(UInt32.max),
            column: 1
        )
        // UInt32.max is a valid positive line number, so Line.Number never throws.
        // swiftlint:disable:next force_try
        let expectedLine = try! Text.Line.Number(Int(UInt32.max))
        #expect(location.line == expectedLine)
    }

    @Test
    func `Location with unicode in fileID`() {
        let location = Source.Location(
            fileID: "测试.swift",
            line: 1,
            column: 1
        )
        #expect(location.fileID == "测试.swift")
    }

    @Test
    func `Location filePath defaults to nil`() {
        let location = Source.Location(
            fileID: "Test.swift",
            line: 1,
            column: 1
        )
        #expect(location.filePath == nil)
    }
}

// MARK: - Integration Tests

extension Source.Location.Test.Integration {
    @Test
    func `Location equality`() {
        let loc1 = Source.Location(
            fileID: "Test.swift",
            line: 42,
            column: 7
        )
        let loc2 = Source.Location(
            fileID: "Test.swift",
            line: 42,
            column: 7
        )
        let loc3 = Source.Location(
            fileID: "Other.swift",
            line: 42,
            column: 7
        )
        let loc4 = Source.Location(
            fileID: "Test.swift",
            line: 100,
            column: 7
        )

        #expect(loc1 == loc2)
        #expect(loc1 != loc3)
        #expect(loc1 != loc4)
    }

    @Test
    func `Location hashability`() {
        let loc1 = Source.Location(
            fileID: "Test.swift",
            line: 42,
            column: 7
        )
        let loc2 = Source.Location(
            fileID: "Test.swift",
            line: 42,
            column: 7
        )

        var set: Set<Source.Location> = []
        set.insert(loc1)
        set.insert(loc2)

        #expect(set.count == 1)
    }
}

// MARK: - Performance Tests

extension Source.Location.Test.Performance {
    @Test
    func `Location creation`() {
        // Warmup
        for _ in 0..<100 {
            _ = Source.Location(
                fileID: "Test.swift",
                line: 42,
                column: 7
            )
        }
        // Measured
        for _ in 0..<1000 {
            for i in 0..<100 {
                _ = Source.Location(
                    fileID: "Test.swift",
                    line: i,
                    column: 1
                )
            }
        }
    }
}
