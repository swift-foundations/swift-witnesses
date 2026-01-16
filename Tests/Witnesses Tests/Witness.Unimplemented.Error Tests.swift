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

extension Witness.Unimplemented.Error {
    #TestSuites
}

// MARK: - Unit Tests

extension Witness.Unimplemented.Error.Test.Unit {
    @Test("Error stores witness, operation, and location")
    func errorStores() {
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
    }

    @Test("Error description contains all info")
    func errorDescription() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)
        let error = Witness.Unimplemented.Error(
            witness: "FileSystem",
            operation: "open(path:flags:)",
            location: location
        )

        #expect(error.description.contains("FileSystem.open(path:flags:)"))
        #expect(error.description.contains("not implemented"))
        #expect(error.description.contains("Test.swift"))
        #expect(error.description.contains("42"))
    }

    @Test("Error conforms to Swift.Error")
    func conformsToError() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)
        let error: any Swift.Error = Witness.Unimplemented.Error(
            witness: "Test",
            operation: "test()",
            location: location
        )

        #expect(error is Witness.Unimplemented.Error)
    }

    @Test("Error is Sendable")
    func sendable() async {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)
        let error = Witness.Unimplemented.Error(
            witness: "FileSystem",
            operation: "open(path:flags:)",
            location: location
        )

        await Task {
            #expect(error.witness == "FileSystem")
        }.value
    }
}

// MARK: - Edge Case Tests

extension Witness.Unimplemented.Error.Test.EdgeCase {
    @Test("Error with empty witness name")
    func emptyWitness() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: 1)
        let error = Witness.Unimplemented.Error(
            witness: "",
            operation: "test()",
            location: location
        )

        #expect(error.witness == "")
        #expect(error.description.contains(".test()"))
    }

    @Test("Error with empty operation name")
    func emptyOperation() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: 1)
        let error = Witness.Unimplemented.Error(
            witness: "Test",
            operation: "",
            location: location
        )

        #expect(error.operation == "")
        #expect(error.description.contains("Test."))
    }

    @Test("Error with complex operation signature")
    func complexOperation() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: 1)
        let error = Witness.Unimplemented.Error(
            witness: "NetworkClient",
            operation: "send(request:headers:timeout:retryPolicy:)",
            location: location
        )

        #expect(error.operation == "send(request:headers:timeout:retryPolicy:)")
        #expect(error.description.contains("send(request:headers:timeout:retryPolicy:)"))
    }

    @Test("Error with unicode in names")
    func unicodeNames() {
        let location = Witness.Unimplemented.Location(fileID: "测试.swift", line: 1)
        let error = Witness.Unimplemented.Error(
            witness: "文件系统",
            operation: "打开(路径:)",
            location: location
        )

        #expect(error.witness == "文件系统")
        #expect(error.operation == "打开(路径:)")
    }
}

// MARK: - Integration Tests

extension Witness.Unimplemented.Error.Test.Integration {
    @Test("Error equality")
    func equality() {
        let loc1 = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)
        let loc2 = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)

        let err1 = Witness.Unimplemented.Error(witness: "A", operation: "b()", location: loc1)
        let err2 = Witness.Unimplemented.Error(witness: "A", operation: "b()", location: loc2)
        let err3 = Witness.Unimplemented.Error(witness: "A", operation: "c()", location: loc1)

        #expect(err1 == err2)
        #expect(err1 != err3)
    }

    @Test("Error hashability")
    func hashability() {
        let loc = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)
        let err1 = Witness.Unimplemented.Error(witness: "A", operation: "b()", location: loc)
        let err2 = Witness.Unimplemented.Error(witness: "A", operation: "b()", location: loc)

        var set: Set<Witness.Unimplemented.Error> = []
        set.insert(err1)
        set.insert(err2)

        #expect(set.count == 1)
    }

    @Test("Error can be caught and rethrown")
    func catchAndRethrow() async throws {
        let api = TestAPI.unimplemented()

        do {
            _ = try await api.fetch(id: 1)
            Issue.record("Expected error")
        } catch let error as Witness.Unimplemented.Error {
            // Can be rethrown
            func rethrowError() throws(Witness.Unimplemented.Error) {
                throw error
            }

            #expect(throws: Witness.Unimplemented.Error.self) {
                try rethrowError()
            }
        }
    }
}

// MARK: - Performance Tests

extension Witness.Unimplemented.Error.Test.Performance {
    @Test("Error creation", .timed(iterations: 1000, warmup: 100))
    func errorCreation() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)
        for _ in 0..<100 {
            _ = Witness.Unimplemented.Error(
                witness: "FileSystem",
                operation: "open(path:flags:)",
                location: location
            )
        }
    }

    @Test("Error description generation", .timed(iterations: 1000, warmup: 100))
    func descriptionGeneration() {
        let location = Witness.Unimplemented.Location(fileID: "Test.swift", line: 42)
        let error = Witness.Unimplemented.Error(
            witness: "FileSystem",
            operation: "open(path:flags:)",
            location: location
        )
        for _ in 0..<100 {
            _ = error.description
        }
    }
}
