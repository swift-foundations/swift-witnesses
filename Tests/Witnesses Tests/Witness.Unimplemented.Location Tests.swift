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
import Testing_Extras
@testable import Witnesses

extension Witness.Unimplemented.Location {
    #TestSuites
}

// MARK: - Unit Tests

extension Witness.Unimplemented.Location.Test.Unit {
    @Test("Location stores fileID and line")
    func locationStores() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)

        #expect(location.fileID == "Test.swift")
        #expect(location.line == 42)
    }

    @Test("Location uses default values from call site")
    func defaultValues() {
        let location = Witness.Unimplemented.Location()

        #expect(location.fileID.contains("Witness.Unimplemented.Location Tests"))
        #expect(location.line > 0)
    }

    @Test("Location is Sendable")
    func sendable() async {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)

        await Task {
            #expect(location.fileID == "Test.swift")
            #expect(location.line == 42)
        }.value
    }
}

// MARK: - Edge Case Tests

extension Witness.Unimplemented.Location.Test.EdgeCase {
    @Test("Location with empty fileID")
    func emptyFileID() {
        let location = Witness.Unimplemented.Location(fileID: "", line: 1)
        #expect(location.fileID == "")
    }

    @Test("Location with zero line")
    func zeroLine() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: 0)
        #expect(location.line == 0)
    }

    @Test("Location with negative line")
    func negativeLine() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: -1)
        #expect(location.line == -1)
    }

    @Test("Location with large line number")
    func largeLine() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: Int.max)
        #expect(location.line == Int.max)
    }

    @Test("Location with unicode in fileID")
    func unicodeFileID() {
        let location = Witness.Unimplemented.Location(fileID: "测试.swift", line: 1)
        #expect(location.fileID == "测试.swift")
    }
}

// MARK: - Integration Tests

extension Witness.Unimplemented.Location.Test.Integration {
    @Test("Location equality")
    func equality() {
        let loc1 = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)
        let loc2 = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)
        let loc3 = Witness.Unimplemented.Location(fileID: "Other.swift", line: 42)
        let loc4 = Witness.Unimplemented.Location(fileID: "Test.swift", line: 100)

        #expect(loc1 == loc2)
        #expect(loc1 != loc3)
        #expect(loc1 != loc4)
    }

    @Test("Location hashability")
    func hashability() {
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
    @Test("Location creation", .timed(iterations: 1000, warmup: 100))
    func locationCreation() {
        for i in 0..<100 {
            _ = Witness.Unimplemented.Location(fileID: "Test.swift", line: i)
        }
    }
}
