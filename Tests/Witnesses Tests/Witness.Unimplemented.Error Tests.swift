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

extension Witness.Unimplemented.Error {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit Tests

extension Witness.Unimplemented.Error.Test.Unit {
    @Test
    func `Error stores witness, operation, and location`() {
        let location = Source.Location(
            fileID: "Test.swift",
            line: 42,
            column: 7
        )
        let error = Witness.Unimplemented.Error(
            witness: "FileSystem",
            operation: "open(path:flags:)",
            location: location
        )

        #expect(error.witness == "FileSystem")
        #expect(error.operation == "open(path:flags:)")
        #expect(error.location.fileID == "Test.swift")
        #expect(error.location.line == 42)
        #expect(error.location.column == 7)
    }

    @Test
    func `Error description contains all info`() {
        let location = Source.Location(
            fileID: "Test.swift",
            line: 42,
            column: 7
        )
        let error = Witness.Unimplemented.Error(
            witness: "FileSystem",
            operation: "open(path:flags:)",
            location: location
        )

        #expect(error.description.contains("FileSystem.open(path:flags:)"))
        #expect(error.description.contains("not implemented"))
        #expect(error.description.contains("Test.swift"))
        #expect(error.description.contains("42"))
        #expect(error.description.contains("7"))
    }

    @Test
    func `Error conforms to Swift.Error`() {
        let location = Source.Location(
            fileID: "Test.swift",
            line: 42,
            column: 7
        )
        let error: any Swift.Error = Witness.Unimplemented.Error(
            witness: "Test",
            operation: "test()",
            location: location
        )

        #expect(error is Witness.Unimplemented.Error)
    }

    @Test
    func `Error is Sendable`() async {
        let location = Source.Location(
            fileID: "Test.swift",
            line: 42,
            column: 7
        )
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
    @Test
    func `Error with empty witness name`() {
        let location = Source.Location(
            fileID: "Test.swift",
            line: 1,
            column: 1
        )
        let error = Witness.Unimplemented.Error(
            witness: "",
            operation: "test()",
            location: location
        )

        #expect(error.witness.isEmpty)
        #expect(error.description.contains(".test()"))
    }

    @Test
    func `Error with empty operation name`() {
        let location = Source.Location(
            fileID: "Test.swift",
            line: 1,
            column: 1
        )
        let error = Witness.Unimplemented.Error(
            witness: "Test",
            operation: "",
            location: location
        )

        #expect(error.operation.isEmpty)
        #expect(error.description.contains("Test."))
    }

    @Test
    func `Error with complex operation signature`() {
        let location = Source.Location(
            fileID: "Test.swift",
            line: 1,
            column: 1
        )
        let error = Witness.Unimplemented.Error(
            witness: "NetworkClient",
            operation: "send(request:headers:timeout:retryPolicy:)",
            location: location
        )

        #expect(error.operation == "send(request:headers:timeout:retryPolicy:)")
        #expect(error.description.contains("send(request:headers:timeout:retryPolicy:)"))
    }

    @Test
    func `Error with unicode in names`() {
        let location = Source.Location(
            fileID: "测试.swift",
            line: 1,
            column: 1
        )
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
    @Test
    func `Error equality`() {
        let loc1 = Source.Location(
            fileID: "Test.swift",
            line: 42,
            column: 7
        )
        let loc2 = Source.Location(
            fileID: "Test.swift",
            line: 42,
            column: 7
        )

        let err1 = Witness.Unimplemented.Error(witness: "A", operation: "b()", location: loc1)
        let err2 = Witness.Unimplemented.Error(witness: "A", operation: "b()", location: loc2)
        let err3 = Witness.Unimplemented.Error(witness: "A", operation: "c()", location: loc1)

        #expect(err1 == err2)
        #expect(err1 != err3)
    }

    @Test
    func `Error hashability`() {
        let loc = Source.Location(
            fileID: "Test.swift",
            line: 42,
            column: 7
        )
        let err1 = Witness.Unimplemented.Error(witness: "A", operation: "b()", location: loc)
        let err2 = Witness.Unimplemented.Error(witness: "A", operation: "b()", location: loc)

        var set: Set<Witness.Unimplemented.Error> = []
        set.insert(err1)
        set.insert(err2)

        #expect(set.count == 1)
    }

    @Test
    func `Error can be caught and rethrown`() async throws {
        let api = TestAPI.unimplemented()

        do throws(Witness.Unimplemented.Error) {
            _ = try await api.fetch(id: 1)
            Issue.record("Expected error")
        } catch {
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
    @Test
    func `Error creation`() {
        let location = Source.Location(
            fileID: "Test.swift",
            line: 42,
            column: 7
        )
        // Warmup
        for _ in 0..<100 {
            _ = Witness.Unimplemented.Error(
                witness: "FileSystem",
                operation: "open(path:flags:)",
                location: location
            )
        }
        // Measured
        for _ in 0..<1000 {
            _ = Witness.Unimplemented.Error(
                witness: "FileSystem",
                operation: "open(path:flags:)",
                location: location
            )
        }
    }

    @Test
    func `Error description generation`() {
        let location = Source.Location(
            fileID: "Test.swift",
            line: 42,
            column: 7
        )
        let error = Witness.Unimplemented.Error(
            witness: "FileSystem",
            operation: "open(path:flags:)",
            location: location
        )
        // Warmup
        for _ in 0..<100 {
            _ = error.description
        }
        // Measured
        for _ in 0..<1000 {
            _ = error.description
        }
    }
}
