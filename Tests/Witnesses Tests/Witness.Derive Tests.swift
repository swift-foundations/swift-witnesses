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

extension Witness.Derive {
    #TestSuites
}

// MARK: - Unit Tests

extension Witness.Derive.Test.Unit {
    @Test("Mock generates static method with value parameters")
    func mockMethodExists() async throws {
        // mock() takes values, not closures
        let api = MockableAPI.mock(
            fetchUser: "Test User",
            getCount: 42
            // deleteUser defaults to () since it returns Void
        )

        // Values are returned regardless of input
        let user = try await api.fetchUser(id: 999)
        #expect(user == "Test User")

        let count = try api.getCount()
        #expect(count == 42)

        // Void operations just work
        try await api.deleteUser(id: 1)
    }

    @Test("Mock with all explicit values")
    func mockWithAllValues() async throws {
        let api = MockableAPI.mock(
            fetchUser: "Explicit User",
            getCount: 100,
            deleteUser: ()
        )

        let user = try await api.fetchUser(id: 1)
        #expect(user == "Explicit User")

        let count = try api.getCount()
        #expect(count == 100)
    }

    @Test("Mock returns same value for any input")
    func mockReturnsSameValue() async throws {
        let api = MockableAPI.mock(
            fetchUser: "Always This",
            getCount: 0
        )

        // Same value regardless of id
        let user1 = try await api.fetchUser(id: 1)
        let user2 = try await api.fetchUser(id: 999)
        let user3 = try await api.fetchUser(id: -1)

        #expect(user1 == "Always This")
        #expect(user2 == "Always This")
        #expect(user3 == "Always This")
    }

    @Test("Mock also has unimplemented available")
    func mockStillHasUnimplemented() async throws {
        // Both mock() and unimplemented() are available
        let mockApi = MockableAPI.mock(fetchUser: "Test", getCount: 0)
        let unimplApi = MockableAPI.unimplemented()

        // Mock works
        let result = try await mockApi.fetchUser(id: 1)
        #expect(result == "Test")

        // Unimplemented throws
        await #expect(throws: Witness.Unimplemented.Error.self) {
            _ = try await unimplApi.fetchUser(id: 1)
        }
    }
}

// MARK: - Edge Case Tests

extension Witness.Derive.Test.EdgeCase {
    @Test("Mock with empty string value")
    func emptyStringMock() async throws {
        let api = MockableAPI.mock(
            fetchUser: "",
            getCount: 0
        )

        let user = try await api.fetchUser(id: 1)
        #expect(user == "")
    }

    @Test("Mock with negative count")
    func negativeCountMock() async throws {
        let api = MockableAPI.mock(
            fetchUser: "User",
            getCount: -1
        )

        let count = try api.getCount()
        #expect(count == -1)
    }

    @Test("Mock with zero count")
    func zeroCountMock() async throws {
        let api = MockableAPI.mock(
            fetchUser: "User",
            getCount: 0
        )

        let count = try api.getCount()
        #expect(count == 0)
    }

    @Test("Mock with large count")
    func largeCountMock() async throws {
        let api = MockableAPI.mock(
            fetchUser: "User",
            getCount: Int.max
        )

        let count = try api.getCount()
        #expect(count == Int.max)
    }
}

// MARK: - Integration Tests

extension Witness.Derive.Test.Integration {
    @Test("Mock in context scope")
    func mockInContext() async throws {
        let mockApi = MockableAPI.mock(
            fetchUser: "Context User",
            getCount: 42
        )

        try await Witness.Context.with { values in
            // Can't test with MockableAPI directly as it doesn't conform to Witness.Key
            // This test validates that mock instances work correctly
        } operation: {
            let user = try await mockApi.fetchUser(id: 1)
            #expect(user == "Context User")
        }
    }

    @Test("Multiple mock instances are independent")
    func multipleMockInstances() async throws {
        let mock1 = MockableAPI.mock(fetchUser: "User 1", getCount: 1)
        let mock2 = MockableAPI.mock(fetchUser: "User 2", getCount: 2)

        let user1 = try await mock1.fetchUser(id: 1)
        let user2 = try await mock2.fetchUser(id: 1)

        #expect(user1 == "User 1")
        #expect(user2 == "User 2")
    }
}

// MARK: - Performance Tests

extension Witness.Derive.Test.Performance {
    @Test("Mock creation", .timed(iterations: 1000, warmup: 100))
    func mockCreation() {
        for _ in 0..<100 {
            _ = MockableAPI.mock(
                fetchUser: "User",
                getCount: 42
            )
        }
    }

    @Test("Mock invocation", .timed(iterations: 1000, warmup: 100))
    func mockInvocation() async throws {
        let api = MockableAPI.mock(
            fetchUser: "User",
            getCount: 42
        )

        for _ in 0..<100 {
            _ = try await api.fetchUser(id: 1)
        }
    }
}
