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

extension Witness.Unimplemented {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct EdgeCase {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit Tests

extension Witness.Unimplemented.Test.Unit {
    @Test
    func `Macro-generated unimplemented throws on invocation`() async throws {
        let api = TestAPI.unimplemented()

        // Calling fetch should throw Witness.Unimplemented.Error
        await #expect(throws: Witness.Unimplemented.Error.self) {
            _ = try await api.fetch(id: 1)
        }

        // Calling update should throw Witness.Unimplemented.Error
        await #expect(throws: Witness.Unimplemented.Error.self) {
            try await api.update(id: 1, value: "test")
        }
    }

    @Test
    func `Macro-generated unimplemented error contains correct info`() async throws {
        let api = TestAPI.unimplemented()

        do {
            _ = try await api.fetch(id: 1)
            Issue.record("Expected error to be thrown")
        } catch let error as Witness.Unimplemented.Error {
            #expect(error.witness == "TestAPI")
            #expect(error.operation == "fetch(id:)")
        }
    }

    @Test
    func `Unimplemented witness can be partially overridden`() async throws {
        var api = TestAPI.unimplemented()

        // Override only fetch
        api.fetch = { id in "Mocked result for \(id)" }

        // fetch works
        let result = try await api.fetch(id: 42)
        #expect(result == "Mocked result for 42")

        // update still throws
        await #expect(throws: Witness.Unimplemented.Error.self) {
            try await api.update(id: 1, value: "test")
        }
    }
}

// MARK: - Edge Case Tests

extension Witness.Unimplemented.Test.EdgeCase {
    @Test
    func `Multiple unimplemented calls have independent locations`() async throws {
        let api1 = TestAPI.unimplemented()
        let api2 = TestAPI.unimplemented()

        do {
            _ = try await api1.fetch(id: 1)
        } catch let error1 as Witness.Unimplemented.Error {
            do {
                _ = try await api2.fetch(id: 1)
            } catch let error2 as Witness.Unimplemented.Error {
                // Both errors should have the same witness and operation
                #expect(error1.witness == error2.witness)
                #expect(error1.operation == error2.operation)
                // But locations may differ (different lines)
            }
        }
    }

    @Test
    func `Override then call non-overridden operation`() async throws {
        var api = TestAPI.unimplemented()
        api.fetch = { _ in "overridden" }

        // Overridden works
        let result = try await api.fetch(id: 1)
        #expect(result == "overridden")

        // Non-overridden still throws
        await #expect(throws: Witness.Unimplemented.Error.self) {
            try await api.update(id: 1, value: "test")
        }
    }
}

// MARK: - Integration Tests

extension Witness.Unimplemented.Test.Integration {
    @Test
    func `Unimplemented in context scope`() async throws {
        try await Witness.Context.with { values in
            values[TestAPI.self] = .unimplemented()
        } operation: {
            let api = Witness.Context.current[TestAPI.self]
            await #expect(throws: Witness.Unimplemented.Error.self) {
                _ = try await api.fetch(id: 1)
            }
        }
    }

    @Test
    func `Partially overridden unimplemented in context`() async throws {
        var unimpl = TestAPI.unimplemented()
        unimpl.fetch = { id in "Context mocked \(id)" }

        try await Witness.Context.with { values in
            values[TestAPI.self] = unimpl
        } operation: {
            let api = Witness.Context.current[TestAPI.self]

            // fetch works
            let result = try await api.fetch(id: 5)
            #expect(result == "Context mocked 5")

            // update throws
            await #expect(throws: Witness.Unimplemented.Error.self) {
                try await api.update(id: 1, value: "test")
            }
        }
    }
}
