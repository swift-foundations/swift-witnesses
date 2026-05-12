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
enum TestCalls: Sendable {
    case load
    case save(path: String)
    case transform(input: Int, scale: Double)
}

/// Enum with keyword case names to test escaping.
@Witness
enum KeywordCalls: Sendable {
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
        let action = TestCalls.load
        #expect(action.load != nil)
        #expect(action.save == nil)
    }

    @Test
    func `Computed property extracts single associated value`() {
        let action = TestCalls.save(path: "/tmp")
        #expect(action.save == "/tmp")
        #expect(action.load == nil)
        #expect(action.transform == nil)
    }

    @Test
    func `Computed property extracts multi-param tuple`() {
        let action = TestCalls.transform(input: 1, scale: 2.0)
        if let t = action.transform {
            #expect(t.input == 1)
            #expect(t.scale == 2.0)
        } else {
            Issue.record("Expected .transform")
        }
    }

    @Test
    func `Case discriminant matches`() {
        #expect(TestCalls.load.case == .load)
        #expect(TestCalls.save(path: "x").case == .save)
        #expect(TestCalls.transform(input: 0, scale: 0).case == .transform)
    }

    @Test
    func `Case count and ordinal`() {
        #expect(TestCalls.Case.count.rawValue == 3)
        #expect(TestCalls.Case.load.ordinal.rawValue == 0)
        #expect(TestCalls.Case.save.ordinal.rawValue == 1)
        #expect(TestCalls.Case.transform.ordinal.rawValue == 2)
    }

    @Test
    func `Case init from ordinal`() throws {
        let c0 = try TestCalls.Case(_unchecked: (), ordinal: .init(0))
        let c1 = try TestCalls.Case(_unchecked: (), ordinal: .init(1))
        let c2 = try TestCalls.Case(_unchecked: (), ordinal: .init(2))
        #expect(c0 == .load)
        #expect(c1 == .save)
        #expect(c2 == .transform)
    }

    @Test
    func `is prism check`() {
        #expect(TestCalls.load.is(\.load) == true)
        #expect(TestCalls.save(path: "x").is(\.load) == false)
        #expect(TestCalls.save(path: "x").is(\.save) == true)
    }

    @Test
    func `Subscript prism extraction`() {
        let action = TestCalls.save(path: "/home")
        #expect(action[prism: \.save] == "/home")
        #expect(action[prism: \.load] == nil)
    }

    @Test
    func `Modify via prism`() {
        var action = TestCalls.save(path: "/old")
        action.modify(\.save) { $0 = "/new" }
        #expect(action.save == "/new")
    }

    @Test
    func `Keyword case names compile and work`() {
        let d = KeywordCalls.default
        #expect(d.`default` != nil)
        #expect(d.`return` == nil)

        let r = KeywordCalls.return(value: "hello")
        #expect(r.`return` == "hello")
        #expect(r.`default` == nil)
    }
}
