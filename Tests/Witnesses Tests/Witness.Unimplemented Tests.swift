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
import Synchronization
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

extension Witness.Unimplemented.Test.Unit {
    @Test
    func `Noncopyable driver unimplemented throws for throwing closures`() throws {
        let driver = NoncopyableDriverAPI.unimplemented()

        #expect(throws: Witness.Unimplemented.Error.self) {
            _ = try driver._create()
        }
        #expect(throws: Witness.Unimplemented.Error.self) {
            _ = try driver._register(NoncopyableHandle(fd: 1), 42)
        }
    }

    @Test
    func `Noncopyable driver Action omits owned params`() {
        // register takes (borrowing NoncopyableHandle, Int32) → only Int32 in Action
        let action = NoncopyableDriverAPI.Action.register(42)
        if case .register(let descriptor) = action {
            #expect(descriptor == 42)
        } else {
            Issue.record("Expected .register")
        }

        // close takes (consuming NoncopyableHandle) → no associated values
        let closeAction = NoncopyableDriverAPI.Action.close
        #expect(closeAction.case == .close)

        // poll takes (borrowing NoncopyableHandle, inout [Int32]) → no associated values
        let pollAction = NoncopyableDriverAPI.Action.poll
        #expect(pollAction.case == .poll)

        // create has no params → no associated values
        let createAction = NoncopyableDriverAPI.Action.create
        #expect(createAction.case == .create)
    }

    @Test
    func `Noncopyable driver Observe forwards ownership correctly`() throws {
        let log = Synchronization.Mutex<[String]>([])

        let base = NoncopyableDriverAPI(
            _create: { NoncopyableHandle(fd: 100) },
            _register: { handle, descriptor in
                return Int(descriptor)
            },
            _poll: { handle, buffer in
                buffer.append(handle.fd)
                return 1
            },
            _close: { handle in
                log.withLock { $0.append("closed fd=\(handle.fd)") }
            }
        )

        let observed = base.observe.before { action in
            log.withLock { $0.append("before:\(action.case)") }
        }

        let h = try observed._create()
        #expect(h.fd == 100)
        let regResult = try observed._register(h, 42)
        #expect(regResult == 42)
        var buffer: [Int32] = []
        _ = try observed._poll(h, &buffer)
        #expect(buffer == [100])
        observed._close(consume h)

        let entries = log.withLock { $0 }
        #expect(entries.contains("before:create"))
        #expect(entries.contains("before:register"))
        #expect(entries.contains("before:poll"))
        #expect(entries.contains("before:close"))
        #expect(entries.contains("closed fd=100"))
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
