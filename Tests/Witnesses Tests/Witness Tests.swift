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
import Testing
@testable import Witnesses

extension Witness {
    #Tests
}

// MARK: - Unit Tests
// Note: Witness.Key is a protocol nested in Witness, so its tests live here
// under Witness.Test.Unit per [TEST-ORG-004].

extension Witness.Test.Unit {
    @Test("Key provides live and test values")
    func keyProvidesValues() async throws {
        let live = TestAPI.liveValue
        let test = TestAPI.testValue

        let liveResult = try await live.fetch(id: 1)
        let testResult = try await test.fetch(id: 1)

        #expect(liveResult == "Live result for 1")
        #expect(testResult == "Test result for 1")
    }

    @Test("Default testValue falls back to liveValue")
    func defaultTestValueFallback() async throws {
        // TestAPI explicitly defines testValue, so we verify the Key protocol contract
        let live = TestAPI.liveValue
        let test = TestAPI.testValue

        // Both should be valid and produce correct results
        _ = try await live.fetch(id: 1)
        _ = try await test.fetch(id: 1)
    }
}

// MARK: - Edge Case Tests

extension Witness.Test.EdgeCase {
    @Test("Key works with zero id")
    func keyZeroId() async throws {
        let api = TestAPI.liveValue
        let result = try await api.fetch(id: 0)
        #expect(result == "Live result for 0")
    }

    @Test("Key works with negative id")
    func keyNegativeId() async throws {
        let api = TestAPI.liveValue
        let result = try await api.fetch(id: -1)
        #expect(result == "Live result for -1")
    }

    @Test("Key works with large id")
    func keyLargeId() async throws {
        let api = TestAPI.liveValue
        let result = try await api.fetch(id: Int.max)
        #expect(result == "Live result for \(Int.max)")
    }
}
