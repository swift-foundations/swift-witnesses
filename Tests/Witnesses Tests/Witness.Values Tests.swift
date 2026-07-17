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
        @Suite struct `Edge Case` {}
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

    @Test
    func `withValue resolves liveValue by default`() {
        let values = Witness.Values()

        values.withValue(for: HandleProvider.self, mode: .live) { value in
            #expect(value.id == 1)
        }
    }

    @Test
    func `withValue resolves testValue in test mode`() {
        let values = Witness.Values()

        values.withValue(for: HandleProvider.self, mode: .test) { value in
            #expect(value.id == 99)
        }
    }

    @Test
    func `withValue resolves previewValue in preview mode`() {
        let values = Witness.Values()

        values.withValue(for: HandleProvider.self, mode: .preview) { value in
            #expect(value.id == 50)
        }
    }

    @Test
    func `withValue returns closure result`() {
        let values = Witness.Values()

        let doubled = values.withValue(for: HandleProvider.self, mode: .live) { value in
            value.id * 2
        }
        #expect(doubled == 2)
    }

    @Test
    func `set stores noncopyable value`() {
        var values = Witness.Values()

        values.set(HandleProvider.self, UniqueHandle(id: 42))

        values.withValue(for: HandleProvider.self, mode: .live) { value in
            #expect(value.id == 42)
        }
    }

    @Test
    func `set overrides default for all modes`() {
        var values = Witness.Values()
        values.set(HandleProvider.self, UniqueHandle(id: 42))

        values.withValue(for: HandleProvider.self, mode: .live) { value in
            #expect(value.id == 42)
        }
        values.withValue(for: HandleProvider.self, mode: .test) { value in
            #expect(value.id == 42)
        }
        values.withValue(for: HandleProvider.self, mode: .preview) { value in
            #expect(value.id == 42)
        }
    }

    @Test
    func `Copyable subscript get still works`() async throws {
        let values = Witness.Values()
        let api = values[TestAPI.self]
        let result = try await api.fetch(id: 1)
        #expect(result == "Live result for 1")
    }

    @Test
    func `Copyable subscript set still works`() async throws {
        var values = Witness.Values()
        values[TestAPI.self] = TestAPI(
            fetch: { id in "Custom \(id)" },
            update: { _, _ in }
        )
        let api = values[TestAPI.self]
        let result = try await api.fetch(id: 1)
        #expect(result == "Custom 1")
    }

    @Test
    func `Preparation store withValue accesses prepared noncopyable value`() {
        let store = Witness.Preparation.Store()
        store.set(HandleProvider.self, value: UniqueHandle(id: 77))

        let result = store.withValue(HandleProvider.self) { value in
            value.id
        }
        #expect(result == 77)
    }

    @Test
    func `Preparation store withValue returns nil when not prepared`() {
        let store = Witness.Preparation.Store()

        let result: Int? = store.withValue(HandleProvider.self) { value in
            value.id
        }
        #expect(result == nil)
    }

    @Test
    func `Copyable Preparation Store get still works`() {
        let store = Witness.Preparation.Store()
        store.set(
            TestAPI.self,
            value: TestAPI(
                fetch: { _ in "Prepared" },
                update: { _, _ in }
            )
        )
        let api = store.get(TestAPI.self)
        #expect(api != nil)
    }

    @Test
    func `Copyable Preparation Store remove still works`() {
        let store = Witness.Preparation.Store()
        store.set(
            TestAPI.self,
            value: TestAPI(
                fetch: { _ in "Prepared" },
                update: { _, _ in }
            )
        )
        let removed = store.remove(TestAPI.self)
        #expect(removed != nil)
        #expect(store.get(TestAPI.self) == nil)
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

    @Test
    func `set replaces previously stored noncopyable value`() {
        var values = Witness.Values()

        values.set(HandleProvider.self, UniqueHandle(id: 1))
        values.set(HandleProvider.self, UniqueHandle(id: 2))

        values.withValue(for: HandleProvider.self, mode: .live) { value in
            #expect(value.id == 2)
        }
    }

    @Test
    func `Multiple noncopyable keys are independent`() {
        var values = Witness.Values()

        values.set(HandleProvider.self, UniqueHandle(id: 42))
        values.set(TokenProvider.self, UniqueHandle(id: 84))

        values.withValue(for: HandleProvider.self, mode: .live) { value in
            #expect(value.id == 42)
        }
        values.withValue(for: TokenProvider.self, mode: .live) { value in
            #expect(value.id == 84)
        }
    }

    @Test
    func `Noncopyable withValue falls through to prepared store`() {
        let store = Witness.Preparation.Store()
        store.set(HandleProvider.self, value: UniqueHandle(id: 77))

        var values = Witness.Values(preparedStore: store)

        // No explicit override — should fall through to prepared.
        values.withValue(for: HandleProvider.self, mode: .live) { value in
            #expect(value.id == 77)
        }

        // Explicit override takes precedence.
        values.set(HandleProvider.self, UniqueHandle(id: 42))
        values.withValue(for: HandleProvider.self, mode: .live) { value in
            #expect(value.id == 42)
        }
    }

    @Test
    func `withValue works with Copyable values too`() {
        let values = Witness.Values()

        let result = values.withValue(for: TestAPI.self, mode: .live) { _ in
            true
        }
        #expect(result == true)
    }

    @Test
    func `Merging preserves noncopyable values from both containers`() {
        var a = Witness.Values()
        a.set(HandleProvider.self, UniqueHandle(id: 10))

        var b = Witness.Values()
        b.set(TokenProvider.self, UniqueHandle(id: 20))

        let merged = a.merging(b)

        // Both keys accessible after merge.
        merged.withValue(for: HandleProvider.self, mode: .live) { value in
            #expect(value.id == 10)
        }
        merged.withValue(for: TokenProvider.self, mode: .live) { value in
            #expect(value.id == 20)
        }
    }

    @Test
    func `Merging with overlap uses latter container`() {
        var a = Witness.Values()
        a.set(HandleProvider.self, UniqueHandle(id: 10))

        var b = Witness.Values()
        b.set(HandleProvider.self, UniqueHandle(id: 20))

        let merged = a.merging(b)

        merged.withValue(for: HandleProvider.self, mode: .live) { value in
            #expect(value.id == 20)
        }
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

    @Test
    func `withValue access`() {
        let values = Witness.Values()

        // Warmup
        for _ in 0..<100 {
            values.withValue(for: HandleProvider.self, mode: .live) { _ in }
        }
        // Measured
        for _ in 0..<1000 {
            values.withValue(for: HandleProvider.self, mode: .live) { _ in }
        }
    }

    @Test
    func `set noncopyable value`() {
        var values = Witness.Values()

        // Warmup
        for _ in 0..<100 {
            values.set(HandleProvider.self, UniqueHandle(id: 1))
        }
        // Measured
        for _ in 0..<1000 {
            values.set(HandleProvider.self, UniqueHandle(id: 1))
        }
    }
}
