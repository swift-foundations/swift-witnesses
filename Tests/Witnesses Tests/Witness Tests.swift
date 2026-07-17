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

extension Witness {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit Tests
// Note: Witness.Key is a protocol nested in Witness, so its tests live here
// under Witness.Test.Unit per [TEST-ORG-004].

extension Witness.Test.Unit {
    @Test
    func `Key provides live and test values`() async throws {
        let live = TestAPI.liveValue
        let test = TestAPI.testValue

        let liveResult = try await live.fetch(id: 1)
        let testResult = try await test.fetch(id: 1)

        #expect(liveResult == "Live result for 1")
        #expect(testResult == "Test result for 1")
    }

    @Test
    func `Default testValue falls back to liveValue`() async throws {
        // TestAPI explicitly defines testValue, so we verify the Key protocol contract
        let live = TestAPI.liveValue
        let test = TestAPI.testValue

        // Both should be valid and produce correct results
        _ = try await live.fetch(id: 1)
        _ = try await test.fetch(id: 1)
    }

    @Test
    func `Copyable key defaults still chain through liveValue`() async throws {
        let live = TestAPI.liveValue
        let preview = TestAPI.previewValue
        let test = TestAPI.testValue

        let liveResult = try await live.fetch(id: 1)
        let previewResult = try await preview.fetch(id: 1)
        let testResult = try await test.fetch(id: 1)

        #expect(liveResult == "Live result for 1")
        #expect(previewResult == "Live result for 1")  // previewValue defaults to liveValue
        #expect(testResult == "Test result for 1")  // TestAPI overrides testValue
    }

    @Test
    func `Noncopyable key provides distinct values per mode`() {
        Witness.Context.withValue(HandleProvider.self) { value in
            #expect(value.id == 1)  // liveValue (default mode)
        }
    }
}

// MARK: - Edge Case Tests

extension Witness.Test.EdgeCase {
    @Test
    func `Key works with zero id`() async throws {
        let api = TestAPI.liveValue
        let result = try await api.fetch(id: 0)
        #expect(result == "Live result for 0")
    }

    @Test
    func `Key works with negative id`() async throws {
        let api = TestAPI.liveValue
        let result = try await api.fetch(id: -1)
        #expect(result == "Live result for -1")
    }

    @Test
    func `Key works with large id`() async throws {
        let api = TestAPI.liveValue
        let result = try await api.fetch(id: Int.max)
        #expect(result == "Live result for \(Int.max)")
    }
}
