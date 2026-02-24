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

extension Witness.Unimplemented.Location {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct EdgeCase {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit Tests

extension Witness.Unimplemented.Location.Test.Unit {
    @Test
    func `Location stores fileID and line`() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)

        #expect(location.fileID == "Test.swift")
        #expect(location.line == 42)
    }

    @Test
    func `Location uses default values from call site`() {
        let location = Witness.Unimplemented.Location()

        #expect(location.fileID.contains("Witness.Unimplemented.Location Tests"))
        #expect(location.line > 0)
    }

    @Test
    func `Location is Sendable`() async {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)

        await Task {
            #expect(location.fileID == "Test.swift")
            #expect(location.line == 42)
        }.value
    }
}

// MARK: - Edge Case Tests

extension Witness.Unimplemented.Location.Test.EdgeCase {
    @Test
    func `Location with empty fileID`() {
        let location = Witness.Unimplemented.Location(fileID: "", line: 1)
        #expect(location.fileID == "")
    }

    @Test
    func `Location with zero line`() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: 0)
        #expect(location.line == 0)
    }

    @Test
    func `Location with negative line`() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: -1)
        #expect(location.line == -1)
    }

    @Test
    func `Location with large line number`() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: Int.max)
        #expect(location.line == Int.max)
    }

    @Test
    func `Location with unicode in fileID`() {
        let location = Witness.Unimplemented.Location(fileID: "测试.swift", line: 1)
        #expect(location.fileID == "测试.swift")
    }
}

// MARK: - Integration Tests

extension Witness.Unimplemented.Location.Test.Integration {
    @Test
    func `Location equality`() {
        let loc1 = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)
        let loc2 = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)
        let loc3 = Witness.Unimplemented.Location(fileID: "Other.swift", line: 42)
        let loc4 = Witness.Unimplemented.Location(fileID: "Test.swift", line: 100)

        #expect(loc1 == loc2)
        #expect(loc1 != loc3)
        #expect(loc1 != loc4)
    }

    @Test
    func `Location hashability`() {
        let loc1 = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)
        let loc2 = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)

        var set: Set<Witness.Unimplemented.Location> = []
        set.insert(loc1)
        set.insert(loc2)

        #expect(set.count == 1)
    }
}

// MARK: - Performance Tests

extension Witness.Unimplemented.Location.Test.Performance {
    @Test
    func `Location creation`() {
        // Warmup
        for _ in 0..<100 {
            _ = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)
        }
        // Measured
        for _ in 0..<1000 {
            for i in 0..<100 {
                _ = Witness.Unimplemented.Location(fileID: "Test.swift", line: i)
            }
        }
    }
}
