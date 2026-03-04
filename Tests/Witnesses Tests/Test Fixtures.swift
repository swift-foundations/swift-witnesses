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
public import Witnesses

/// Test witness for basic operations.
@Witness
struct TestAPI: Sendable {
    var fetch: @Sendable (_ id: Int) async throws(Witness.Unimplemented.Error) -> String
    var update: @Sendable (_ id: Int, _ value: String) async throws(Witness.Unimplemented.Error) -> Void
}

/// Test witness with mock derive option.
@Witness(.mock)
struct MockableAPI: Sendable {
    var fetchUser: @Sendable (_ id: Int) async throws(Witness.Unimplemented.Error) -> String
    var getCount: @Sendable () throws(Witness.Unimplemented.Error) -> Int
    var deleteUser: @Sendable (_ id: Int) async throws(Witness.Unimplemented.Error) -> Void
}

// MARK: - Ownership Convention Fixtures

/// A simple handle type for testing ownership parameter conventions.
struct SomeHandle: Sendable {
    let id: Int
}

/// Witness with borrowing/consuming/inout parameter conventions.
@Witness
struct OwnershipAPI: Sendable {
    var borrow: @Sendable (_ handle: borrowing SomeHandle) throws(Witness.Unimplemented.Error) -> Int
    var consume: @Sendable (_ handle: consuming SomeHandle) throws(Witness.Unimplemented.Error) -> Void
    var mutate: @Sendable (_ buffer: inout [UInt8]) throws(Witness.Unimplemented.Error) -> Int
    var mixed: @Sendable (_ handle: borrowing SomeHandle, _ count: Int, _ buffer: inout [UInt8]) throws(Witness.Unimplemented.Error) -> Void
}

// MARK: - ~Copyable Witness Fixtures

/// A ~Copyable witness value representing a unique, non-shareable resource.
struct UniqueHandle: ~Copyable, Sendable {
    let id: Int
}

/// Witness key providing ~Copyable values.
///
/// Because `Value` is `~Copyable`, the key must provide explicit implementations
/// for `liveValue`, `testValue`, and `previewValue` — the protocol defaults
/// are constrained to `where Value: Copyable`.
struct HandleProvider: Witness.Key, Sendable {
    typealias Value = UniqueHandle

    static var liveValue: UniqueHandle { UniqueHandle(id: 1) }
    static var testValue: UniqueHandle { UniqueHandle(id: 99) }
    static var previewValue: UniqueHandle { UniqueHandle(id: 50) }
}

/// A second ~Copyable key to test multi-key independence.
struct TokenProvider: Witness.Key, Sendable {
    typealias Value = UniqueHandle

    static var liveValue: UniqueHandle { UniqueHandle(id: 1000) }
    static var testValue: UniqueHandle { UniqueHandle(id: 9999) }
    static var previewValue: UniqueHandle { UniqueHandle(id: 5000) }
}

// MARK: - Copyable Witness Fixtures

// MARK: - Driver Pattern Fixtures (let closures, _ prefix, non-closure properties)

/// Witness with let closures, _ prefix, non-closure properties (IO driver pattern).
@Witness
struct DriverPatternAPI: Sendable {
    let capabilities: Int
    let _create: @Sendable () throws(Witness.Unimplemented.Error) -> String
    let _operate: @Sendable (_ handle: borrowing SomeHandle, _ count: Int) throws(Witness.Unimplemented.Error) -> Void
    let _close: @Sendable (_ handle: consuming SomeHandle) throws(Witness.Unimplemented.Error) -> Void
}

// MARK: - ~Copyable Driver Pattern Fixture

/// A ~Copyable handle mimicking IO.Event.Driver.Handle.
struct NoncopyableHandle: ~Copyable, Sendable {
    let fd: Int32
}

/// Witness with ~Copyable ownership patterns matching IO.Event.Driver's shape.
/// Tests the omission pattern: borrowing/consuming/inout params are omitted from Action.
@Witness
struct NoncopyableDriverAPI: Sendable {
    let _create: @Sendable () throws(Witness.Unimplemented.Error) -> NoncopyableHandle
    let _register: @Sendable (borrowing NoncopyableHandle, Int32) throws(Witness.Unimplemented.Error) -> Int
    let _poll: @Sendable (borrowing NoncopyableHandle, inout [Int32]) throws(Witness.Unimplemented.Error) -> Int
    let _close: @Sendable (consuming NoncopyableHandle) -> Void
}

// MARK: - Existing Init Fixture

/// Witness with existing init (macro should skip init generation).
@Witness
struct ExistingInitAPI: Sendable {
    var fetch: @Sendable (_ id: Int) throws(Witness.Unimplemented.Error) -> String

    init(fetch: @escaping @Sendable (_ id: Int) throws(Witness.Unimplemented.Error) -> String) {
        self.fetch = fetch
    }
}

// MARK: - Generator Pattern Fixture

@Witness(.generator)
struct IntGenerator: Sendable {
    var generate: @Sendable () throws(Witness.Unimplemented.Error) -> Int
}

// MARK: - Foreign Error Type Fixture

enum CustomError: Error, Sendable { case failed }

// MARK: - Nested Type Fixture

enum APINamespace {
    @Witness
    struct Client: Sendable {
        var fetch: @Sendable (_ id: Int) throws(Witness.Unimplemented.Error) -> String
    }
}

// MARK: - Witness.Key Fixtures

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
