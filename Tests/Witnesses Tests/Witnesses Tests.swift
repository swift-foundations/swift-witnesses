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
import Witnesses

// MARK: - Test Witness

@Witness
struct TestAPI: Sendable {
    var fetch: @Sendable (_ id: Int) async throws -> String
    var update: @Sendable (_ id: Int, _ value: String) async throws -> Void
}

extension TestAPI: Witness.Key {
    static var liveValue: TestAPI {
        TestAPI(
            fetch: { id in "Live result for \(id)" },
            update: { _, _ in }
        )
    }

    static var testValue: TestAPI {
        TestAPI(
            fetch: { id in "Test result for \(id)" },
            update: { _, _ in }
        )
    }
}

// MARK: - Tests

@Suite("Witness.Key")
struct WitnessKeyTests {
    @Test("Key provides live and test values")
    func keyValues() async throws {
        let live = TestAPI.liveValue
        let test = TestAPI.testValue

        let liveResult = try await live.fetch(id: 1)
        let testResult = try await test.fetch(id: 1)

        #expect(liveResult == "Live result for 1")
        #expect(testResult == "Test result for 1")
    }
}

@Suite("Witness.Values")
struct WitnessValuesTests {
    @Test("Values container stores and retrieves witnesses")
    func valuesStorage() async throws {
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

    @Test("Test context returns testValue by default")
    func testContext() async throws {
        let values = Witness.Values(isTestContext: true)

        let api = values[TestAPI.self]
        let result = try await api.fetch(id: 1)
        #expect(result == "Test result for 1")
    }
}

@Suite("Witness.Context")
struct WitnessContextTests {
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
        try await Witness.Context.withTest { values in
            // Don't override, just use test defaults
        } operation: {
            let api = Witness.Context.current[TestAPI.self]
            let result = try await api.fetch(id: 1)
            #expect(result == "Test result for 1")
        }
    }
}

@Suite("Witness.Unimplemented")
struct WitnessUnimplementedTests {
    @Test("Unimplemented error provides context")
    func unimplementedError() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)
        let error = Witness.Unimplemented.Error(
            witness: "FileSystem",
            operation: "open(path:flags:)",
            location: location
        )

        #expect(error.witness == "FileSystem")
        #expect(error.operation == "open(path:flags:)")
        #expect(error.location.fileID == "Test.swift")
        #expect(error.location.line == 42)
        #expect(error.description.contains("FileSystem.open(path:flags:)"))
        #expect(error.description.contains("not implemented"))
    }
}
