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

extension Witness.Context {
    #TestSuites
}

// MARK: - Unit Tests

extension Witness.Context.Test.Unit {
    @Test("Context scoped override")
    func scopedOverride() async throws {
        // Outside scope, uses default
        let defaultAPI = Witness.Context.current[TestAPI.self]
        let defaultResult = try await defaultAPI.fetch(id: 1)
        #expect(defaultResult == "Live result for 1")

        // Inside scope, uses override
        try await Witness.Context.with { values in
            values[TestAPI.self] = TestAPI(
                fetch: { id in "Scoped result for \(id)" },
                update: { _, _ in }
            )
        } operation: {
            let scopedAPI = Witness.Context.current[TestAPI.self]
            let scopedResult = try await scopedAPI.fetch(id: 1)
            #expect(scopedResult == "Scoped result for 1")
        }

        // After scope, back to default
        let afterAPI = Witness.Context.current[TestAPI.self]
        let afterResult = try await afterAPI.fetch(id: 1)
        #expect(afterResult == "Live result for 1")
    }

    @Test("Test context provides testValue")
    func testContextScope() async throws {
        await Witness.Context.withTest {
            // Use Witness.Context[key] to get mode-aware access
            let api = Witness.Context[TestAPI.self]
            let result = try? await api.fetch(id: 1)
            #expect(result == "Test result for 1")
        }
    }

    @Test("Current returns default values outside scope")
    func currentOutsideScope() async throws {
        let api = Witness.Context.current[TestAPI.self]
        let result = try await api.fetch(id: 1)
        #expect(result == "Live result for 1")
    }
}

// MARK: - Edge Case Tests

extension Witness.Context.Test.EdgeCase {
    @Test("Nested scopes override correctly")
    func nestedScopes() async throws {
        try await Witness.Context.with { values in
            values[TestAPI.self] = TestAPI(
                fetch: { _ in "Outer" },
                update: { _, _ in }
            )
        } operation: {
            let outer = Witness.Context.current[TestAPI.self]
            let outerResult = try await outer.fetch(id: 1)
            #expect(outerResult == "Outer")

            try await Witness.Context.with { values in
                values[TestAPI.self] = TestAPI(
                    fetch: { _ in "Inner" },
                    update: { _, _ in }
                )
            } operation: {
                let inner = Witness.Context.current[TestAPI.self]
                let innerResult = try await inner.fetch(id: 1)
                #expect(innerResult == "Inner")
            }

            // Back to outer
            let afterInner = Witness.Context.current[TestAPI.self]
            let afterInnerResult = try await afterInner.fetch(id: 1)
            #expect(afterInnerResult == "Outer")
        }
    }

    @Test("Empty modification preserves values")
    func emptyModification() async throws {
        try await Witness.Context.with { _ in
            // No modifications
        } operation: {
            let api = Witness.Context.current[TestAPI.self]
            let result = try await api.fetch(id: 1)
            #expect(result == "Live result for 1")
        }
    }

    @Test("Test context with additional overrides")
    func testContextWithOverrides() async throws {
        try await Witness.Context.withTest { values in
            values[TestAPI.self] = TestAPI(
                fetch: { _ in "Custom in test" },
                update: { _, _ in }
            )
        } operation: {
            let api = Witness.Context.current[TestAPI.self]
            let result = try await api.fetch(id: 1)
            #expect(result == "Custom in test")
        }
    }
}

// MARK: - Integration Tests

extension Witness.Context.Test.Integration {
    @Test("Synchronous with operation works")
    func synchronousOperation() throws {
        let result = try Witness.Context.with { values in
            values[TestAPI.self] = TestAPI(
                fetch: { _ in "Sync" },
                update: { _, _ in }
            )
        } operation: {
            "completed"
        }
        #expect(result == "completed")
    }

    @Test("Async operation preserves context across await")
    func asyncContextPreservation() async throws {
        try await Witness.Context.with { values in
            values[TestAPI.self] = TestAPI(
                fetch: { _ in "Async context" },
                update: { _, _ in }
            )
        } operation: {
            // First access
            let api1 = Witness.Context.current[TestAPI.self]
            let result1 = try await api1.fetch(id: 1)
            #expect(result1 == "Async context")

            // Simulate async work
            try await Task.sleep(for: .milliseconds(1))

            // Second access after await
            let api2 = Witness.Context.current[TestAPI.self]
            let result2 = try await api2.fetch(id: 2)
            #expect(result2 == "Async context")
        }
    }
}

// MARK: - Performance Tests

extension Witness.Context.Test.Performance {
    @Test("Scoped override overhead", .timed(iterations: 100, warmup: 10))
    func scopedOverrideOverhead() {
        _ = Witness.Context.with { _ in } operation: {
            42
        }
    }

    @Test("Current access", .timed(iterations: 1000, warmup: 100))
    func currentAccess() {
        for _ in 0..<100 {
            _ = Witness.Context.current[TestAPI.self]
        }
    }
}
