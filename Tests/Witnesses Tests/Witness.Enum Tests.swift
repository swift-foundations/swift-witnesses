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

// MARK: - Enum Expansion Fixtures

@Witness
enum TestAction: Sendable {
    case load
    case save(path: String)
    case transform(input: Int, scale: Double)
}

/// Enum with keyword case names to test escaping.
@Witness
enum KeywordAction: Sendable {
    case `default`
    case `return`(value: String)
}

extension Witness {
    @Suite
    struct EnumTest {
        @Suite struct Unit {}
    }
}

// MARK: - Unit Tests

extension Witness.EnumTest.Unit {
    @Test
    func `Computed property extracts Void for parameterless case`() {
        let action = TestAction.load
        #expect(action.load != nil)
        #expect(action.save == nil)
    }

    @Test
    func `Computed property extracts single associated value`() {
        let action = TestAction.save(path: "/tmp")
        #expect(action.save == "/tmp")
        #expect(action.load == nil)
        #expect(action.transform == nil)
    }

    @Test
    func `Computed property extracts multi-param tuple`() {
        let action = TestAction.transform(input: 1, scale: 2.0)
        if let t = action.transform {
            #expect(t.input == 1)
            #expect(t.scale == 2.0)
        } else {
            Issue.record("Expected .transform")
        }
    }

    @Test
    func `Case discriminant matches`() {
        #expect(TestAction.load.case == .load)
        #expect(TestAction.save(path: "x").case == .save)
        #expect(TestAction.transform(input: 0, scale: 0).case == .transform)
    }

    @Test
    func `Case count and ordinal`() {
        #expect(TestAction.Case.count.rawValue == 3)
        #expect(TestAction.Case.load.ordinal.rawValue == 0)
        #expect(TestAction.Case.save.ordinal.rawValue == 1)
        #expect(TestAction.Case.transform.ordinal.rawValue == 2)
    }

    @Test
    func `Case init from ordinal`() throws {
        let c0 = try TestAction.Case(__unchecked: (), ordinal: .init(0))
        let c1 = try TestAction.Case(__unchecked: (), ordinal: .init(1))
        let c2 = try TestAction.Case(__unchecked: (), ordinal: .init(2))
        #expect(c0 == .load)
        #expect(c1 == .save)
        #expect(c2 == .transform)
    }

    @Test
    func `is prism check`() {
        #expect(TestAction.load.is(\.load) == true)
        #expect(TestAction.save(path: "x").is(\.load) == false)
        #expect(TestAction.save(path: "x").is(\.save) == true)
    }

    @Test
    func `Subscript prism extraction`() {
        let action = TestAction.save(path: "/home")
        #expect(action[prism: \.save] == "/home")
        #expect(action[prism: \.load] == nil)
    }

    @Test
    func `Modify via prism`() {
        var action = TestAction.save(path: "/old")
        action.modify(\.save) { $0 = "/new" }
        #expect(action.save == "/new")
    }

    @Test
    func `Keyword case names compile and work`() {
        let d = KeywordAction.default
        #expect(d.`default` != nil)
        #expect(d.`return` == nil)

        let r = KeywordAction.return(value: "hello")
        #expect(r.`return` == "hello")
        #expect(r.`default` == nil)
    }
}
