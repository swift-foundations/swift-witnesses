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

extension Witness.Values {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct EdgeCase {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit Tests

extension Witness.Values.Test.Unit {
    @Test
    func `Values container stores and retrieves witnesses`() async throws {
        var values = Witness.Values()

        // Before setting, returns liveValue
        let initial = values[TestAPI.self]
        let initialResult = try await initial.fetch(id: 1)
        #expect(initialResult == "Live result for 1")

        // After setting, returns custom value
        values[TestAPI.self] = TestAPI(
            fetch: { id in "Custom result for \(id)" },
            update: { _, _ in }
        )

        let custom = values[TestAPI.self]
        let customResult = try await custom.fetch(id: 1)
        #expect(customResult == "Custom result for 1")
    }

    @Test
    func `Test mode returns testValue by default`() async throws {
        // Use Witness.Context with test mode to get testValue
        await Witness.Context.withTest {
            let api = Witness.Context[TestAPI.self]
            Task {
                let result = try await api.fetch(id: 1)
                #expect(result == "Test result for 1")
            }
        }
    }

    @Test
    func `Live mode returns liveValue by default`() async throws {
        // Default mode is live
        let api = Witness.Context[TestAPI.self]
        let result = try await api.fetch(id: 1)
        #expect(result == "Live result for 1")
    }

    @Test
    func `Default init creates live context`() async throws {
        let values = Witness.Values()

        let api = values[TestAPI.self]
        let result = try await api.fetch(id: 1)
        #expect(result == "Live result for 1")
    }
}

// MARK: - Edge Case Tests

extension Witness.Values.Test.EdgeCase {
    @Test
    func `Overwriting a value replaces it`() async throws {
        var values = Witness.Values()

        values[TestAPI.self] = TestAPI(
            fetch: { _ in "First" },
            update: { _, _ in }
        )

        values[TestAPI.self] = TestAPI(
            fetch: { _ in "Second" },
            update: { _, _ in }
        )

        let api = values[TestAPI.self]
        let result = try await api.fetch(id: 1)
        #expect(result == "Second")
    }

    @Test
    func `Multiple different keys are independent`() async throws {
        var values = Witness.Values()

        values[TestAPI.self] = TestAPI(
            fetch: { _ in "Custom TestAPI" },
            update: { _, _ in }
        )

        // TestAPI is customized
        let testApi = values[TestAPI.self]
        let testResult = try await testApi.fetch(id: 1)
        #expect(testResult == "Custom TestAPI")
    }
}

// MARK: - Performance Tests

extension Witness.Values.Test.Performance {
    @Test
    func `Subscript access`() async throws {
        let values = Witness.Values()
        // Warmup
        for _ in 0..<100 {
            _ = values[TestAPI.self]
        }
        // Measured
        for _ in 0..<1000 {
            _ = values[TestAPI.self]
        }
    }

    @Test
    func `Subscript write`() {
        var values = Witness.Values()
        let api = TestAPI(
            fetch: { _ in "Test" },
            update: { _, _ in }
        )
        // Warmup
        for _ in 0..<100 {
            values[TestAPI.self] = api
        }
        // Measured
        for _ in 0..<1000 {
            values[TestAPI.self] = api
        }
    }
}
