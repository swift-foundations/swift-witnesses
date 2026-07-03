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

extension Witness.Context {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct EdgeCase {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit Tests

extension Witness.Context.Test.Unit {
    @Test
    func `Context scoped override`() async throws {
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

    @Test
    func `Test context provides testValue`() async throws {
        await Witness.Context.withTest {
            // Use Witness.Context[key] to get mode-aware access
            let api = Witness.Context[TestAPI.self]
            let result = try? await api.fetch(id: 1)
            #expect(result == "Test result for 1")
        }
    }

    @Test
    func `Current returns default values outside scope`() async throws {
        let api = Witness.Context.current[TestAPI.self]
        let result = try await api.fetch(id: 1)
        #expect(result == "Live result for 1")
    }

    @Test
    func `withValue resolves noncopyable from current context`() {
        let id = Witness.Context.withValue(HandleProvider.self) { value in
            value.id
        }
        #expect(id == 1)  // Default live mode
    }

    @Test
    func `withValue respects test mode`() {
        Witness.Context.withTest {
            let id = Witness.Context.withValue(HandleProvider.self) { value in
                value.id
            }
            #expect(id == 99)
        }
    }

    @Test
    func `withValue respects preview mode`() {
        Witness.Context.withPreview {
            let id = Witness.Context.withValue(HandleProvider.self) { value in
                value.id
            }
            #expect(id == 50)
        }
    }

    @Test
    func `Copyable Context subscript still works`() async throws {
        let api = Witness.Context[TestAPI.self]
        let result = try await api.fetch(id: 1)
        #expect(result == "Live result for 1")
    }

    @Test
    func `Copyable Context value still works`() async throws {
        let result = Witness.Context.value(TestAPI.self)
        switch result {
        case .success(let api):
            let fetchResult = try await api.fetch(id: 1)
            #expect(fetchResult == "Live result for 1")

        case .failure:
            Issue.record("Expected success")
        }
    }
}

// MARK: - Edge Case Tests

extension Witness.Context.Test.EdgeCase {
    @Test
    func `Nested scopes override correctly`() async throws {
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

    @Test
    func `Empty modification preserves values`() async throws {
        try await Witness.Context.with { _ in
            // No modifications
        } operation: {
            let api = Witness.Context.current[TestAPI.self]
            let result = try await api.fetch(id: 1)
            #expect(result == "Live result for 1")
        }
    }

    @Test
    func `Test context with additional overrides`() async throws {
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
    @Test
    func `Synchronous with operation works`() throws {
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

    @Test
    func `Async operation preserves context across await`() async throws {
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

    @Test
    func `Context scope with noncopyable override via set`() {
        Witness.Context.with { values in
            values.set(HandleProvider.self, UniqueHandle(id: 42))
        } operation: {
            let id = Witness.Context.withValue(HandleProvider.self) { value in
                value.id
            }
            #expect(id == 42)
        }
    }

    @Test
    func `Nested context scopes with noncopyable override`() {
        Witness.Context.with { values in
            values.set(HandleProvider.self, UniqueHandle(id: 10))
        } operation: {
            let outer = Witness.Context.withValue(HandleProvider.self) { $0.id }
            #expect(outer == 10)

            Witness.Context.with { values in
                values.set(HandleProvider.self, UniqueHandle(id: 20))
            } operation: {
                let inner = Witness.Context.withValue(HandleProvider.self) { $0.id }
                #expect(inner == 20)
            }

            // Restored after inner scope.
            let restored = Witness.Context.withValue(HandleProvider.self) { $0.id }
            #expect(restored == 10)
        }
    }

    @Test
    func `Test mode with noncopyable key resolves testValue`() {
        Witness.Context.withTest {
            let id = Witness.Context.withValue(HandleProvider.self) { $0.id }
            #expect(id == 99)
        }
    }

    @Test
    func `Preview mode with noncopyable key resolves previewValue`() {
        Witness.Context.withPreview {
            let id = Witness.Context.withValue(HandleProvider.self) { $0.id }
            #expect(id == 50)
        }
    }

    @Test
    func `Mode override combined with explicit set`() {
        Witness.Context.with(mode: .test) { values in
            values.set(HandleProvider.self, UniqueHandle(id: 42))
        } operation: {
            let id = Witness.Context.withValue(HandleProvider.self) { $0.id }
            #expect(id == 42)
        }
    }

    @Test
    func `Copyable and noncopyable keys coexist in same context`() async throws {
        try await Witness.Context.with { values in
            values[TestAPI.self] = TestAPI(
                fetch: { id in "Custom \(id)" },
                update: { _, _ in }
            )
            values.set(HandleProvider.self, UniqueHandle(id: 42))
        } operation: {
            // Copyable via subscript
            let api = Witness.Context[TestAPI.self]
            let fetchResult = try await api.fetch(id: 1)
            #expect(fetchResult == "Custom 1")

            // Noncopyable via withValue
            let handleId = Witness.Context.withValue(HandleProvider.self) { $0.id }
            #expect(handleId == 42)
        }
    }
}

// MARK: - Performance Tests

extension Witness.Context.Test.Performance {
    @Test
    func `Scoped override overhead`() {
        // Warmup
        for _ in 0..<10 {
            _ = Witness.Context.with { _ in
            } operation: {
                42
            }
        }
        // Measured
        for _ in 0..<100 {
            _ = Witness.Context.with { _ in
            } operation: {
                42
            }
        }
    }

    @Test
    func `Current access`() {
        // Warmup
        for _ in 0..<100 {
            _ = Witness.Context.current[TestAPI.self]
        }
        // Measured
        for _ in 0..<1000 {
            _ = Witness.Context.current[TestAPI.self]
        }
    }

    @Test
    func `Context withValue noncopyable`() {
        // Warmup
        for _ in 0..<100 {
            Witness.Context.withValue(HandleProvider.self) { _ in }
        }
        // Measured
        for _ in 0..<1000 {
            Witness.Context.withValue(HandleProvider.self) { _ in }
        }
    }
}
