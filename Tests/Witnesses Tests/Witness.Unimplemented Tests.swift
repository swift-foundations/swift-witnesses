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

import Synchronization
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

extension Witness.Unimplemented.Test.Unit {
    @Test
    func `Noncopyable driver unimplemented throws for throwing closures`() throws {
        let driver = NoncopyableDriverAPI.unimplemented()

        #expect(throws: Witness.Unimplemented.Error.self) {
            _ = try driver.create()
        }
        #expect(throws: Witness.Unimplemented.Error.self) {
            _ = try driver.register(NoncopyableHandle(fd: 1), 42)
        }
    }

    @Test
    func `Noncopyable driver Calls omits owned params`() {
        // register takes (borrowing NoncopyableHandle, Int32) → only Int32 in Calls
        let action = NoncopyableDriverAPI.Calls.register(42)
        if case .register(let descriptor) = action {
            #expect(descriptor == 42)
        } else {
            Issue.record("Expected .register")
        }

        // close takes (consuming NoncopyableHandle) → no associated values
        let closeCalls = NoncopyableDriverAPI.Calls.close
        #expect(closeCalls.case == .close)

        // poll takes (borrowing NoncopyableHandle, inout [Int32]) → no associated values
        let pollCalls = NoncopyableDriverAPI.Calls.poll
        #expect(pollCalls.case == .poll)

        // create has no params → no associated values
        let createCalls = NoncopyableDriverAPI.Calls.create
        #expect(createCalls.case == .create)
    }

    @Test
    func `Noncopyable driver Result carries actual return types`() throws {
        let handle = NoncopyableHandle(fd: 42)
        let result = NoncopyableDriverAPI.Result.create(
            Standard_Library_Extensions.Result<NoncopyableHandle, Witness.Unimplemented.Error>.success(handle)
        )
        switch consume result {
        case .create(.success(let h)):
            #expect(h.fd == 42)

        default:
            Issue.record("Expected .create(.success)")
        }
    }

    @Test
    func `Noncopyable driver Observe after works with borrowing`() throws {
        let log = Synchronization.Mutex<[String]>([])

        let base = NoncopyableDriverAPI(
            create: { NoncopyableHandle(fd: 55) },
            register: { _, descriptor in Int(descriptor) },
            poll: { handle, buffer in
                buffer.append(handle.fd)
                return 1
            },
            close: { handle in
                log.withLock { $0.append("closed fd=\(handle.fd)") }
            }
        )

        // This was previously impossible: observe.after with ~Copyable return types
        let observed = base.observe.after { outcome in
            log.withLock { $0.append("after:\(outcome.action.case)") }
        }

        let h = try observed.create()
        #expect(h.fd == 55)
        let regResult = try observed.register(h, 42)
        #expect(regResult == 42)
        var buffer: [Int32] = []
        _ = try observed.poll(h, &buffer)
        observed.close(consume h)

        let entries = log.withLock { $0 }
        #expect(entries.contains("after:create"))
        #expect(entries.contains("after:register"))
        #expect(entries.contains("after:poll"))
        #expect(entries.contains("after:close"))
        #expect(entries.contains("closed fd=55"))
    }

    @Test
    func `Noncopyable driver Observe forwards ownership correctly`() throws {
        let log = Synchronization.Mutex<[String]>([])

        let base = NoncopyableDriverAPI(
            create: { NoncopyableHandle(fd: 100) },
            register: { _, descriptor in
                return Int(descriptor)
            },
            poll: { handle, buffer in
                buffer.append(handle.fd)
                return 1
            },
            close: { handle in
                log.withLock { $0.append("closed fd=\(handle.fd)") }
            }
        )

        let observed = base.observe.before { action in
            log.withLock { $0.append("before:\(action.case)") }
        }

        let h = try observed.create()
        #expect(h.fd == 100)
        let regResult = try observed.register(h, 42)
        #expect(regResult == 42)
        var buffer: [Int32] = []
        _ = try observed.poll(h, &buffer)
        #expect(buffer == [100])
        observed.close(consume h)

        let entries = log.withLock { $0 }
        #expect(entries.contains("before:create"))
        #expect(entries.contains("before:register"))
        #expect(entries.contains("before:poll"))
        #expect(entries.contains("before:close"))
        #expect(entries.contains("closed fd=100"))
    }
}

// MARK: - Optional Closure Tests

extension Witness.Unimplemented.Test.Unit {
    @Test
    func `Optional closure unimplemented produces nil`() {
        let api = OptionalCallbackAPI.unimplemented()
        #expect(api.onClose == nil)

        // onEvent still throws
        #expect(throws: Witness.Unimplemented.Error.self) {
            try api.onEvent(name: "test")
        }
    }

    @Test
    func `Optional closure can be set on unimplemented instance`() {
        let called = Synchronization.Mutex(false)
        var api = OptionalCallbackAPI.unimplemented()
        api.onClose = { called.withLock { $0 = true } }
        api.onClose?()
        #expect(called.withLock { $0 })
    }

    @Test
    func `Optional closure init defaults to nil`() {
        let api = OptionalCallbackAPI(
            onEvent: { _ in }
        )
        #expect(api.onClose == nil)
    }

    @Test
    func `Optional closure observe before passes nil through`() throws(Witness.Unimplemented.Error) {
        let log = Synchronization.Mutex<[String]>([])
        let base = OptionalCallbackAPI(
            onEvent: { _ in },
            onClose: nil
        )
        let observed = base.observe.before { action in
            log.withLock { $0.append("before:\(action.case)") }
        }
        // onClose is nil — should remain nil after observe
        #expect(observed.onClose == nil)

        // onEvent triggers observer
        try observed.onEvent(name: "test")
        let entries = log.withLock { $0 }
        #expect(entries == ["before:onEvent"])
    }

    @Test
    func `Optional closure observe wraps non-nil closure`() {
        let log = Synchronization.Mutex<[String]>([])
        let closeCalled = Synchronization.Mutex(false)
        let base = OptionalCallbackAPI(
            onEvent: { _ in },
            onClose: { closeCalled.withLock { $0 = true } }
        )
        let observed = base.observe.before { action in
            log.withLock { $0.append("before:\(action.case)") }
        }
        // onClose is non-nil — should trigger observer and original
        observed.onClose?()
        #expect(closeCalled.withLock { $0 })
        let entries = log.withLock { $0 }
        #expect(entries == ["before:onClose"])
    }

    @Test
    func `Optional closure observe after wraps non-nil closure`() {
        let log = Synchronization.Mutex<[String]>([])
        let closeCalled = Synchronization.Mutex(false)
        let base = OptionalCallbackAPI(
            onEvent: { _ in },
            onClose: { closeCalled.withLock { $0 = true } }
        )
        let observed = base.observe.after { outcome in
            log.withLock { $0.append("after:\(outcome.action.case)") }
        }
        observed.onClose?()
        #expect(closeCalled.withLock { $0 })
        let entries = log.withLock { $0 }
        #expect(entries == ["after:onClose"])
    }
}

// MARK: - Access Level Tests

extension Witness.Unimplemented.Test.Unit {
    @Test
    func `Restricted access struct compiles and works`() {
        // Compile-only: verifies that @Witness with package property
        // doesn't produce @usableFromInline on the restricted property
        let api = RestrictedAccessAPI.unimplemented()
        // open should throw
        #expect(throws: Witness.Unimplemented.Error.self) {
            try api.open()
        }
    }
}

// MARK: - Nonisolated Nonsending Tests

extension Witness.Unimplemented.Test.Unit {
    @Test
    func `Nonsending witness unimplemented compiles and throws`() async throws {
        let api = NonsendingAPI.unimplemented()

        await #expect(throws: Witness.Unimplemented.Error.self) {
            _ = try await api.run(id: 1)
        }

        #expect(throws: Witness.Unimplemented.Error.self) {
            _ = try api.sync()
        }
    }

    @Test
    func `Nonsending witness direct construction and invocation`() async throws {
        let api = NonsendingAPI(
            run: { id in "result-\(id)" },
            shutdown: {},
            sync: { 42 }
        )

        let result = try await api.run(id: 5)
        #expect(result == "result-5")

        let syncResult = try api.sync()
        #expect(syncResult == 42)
    }

    @Test
    func `Nonsending witness observe before passes through nonsending closures`() async throws {
        let log = Synchronization.Mutex<[String]>([])
        let base = NonsendingAPI(
            run: { id in "result-\(id)" },
            shutdown: {},
            sync: { 42 }
        )
        let observed = base.observe.before { action in
            log.withLock { $0.append("before:\(action.case)") }
        }

        // Nonsending closures are passed through (no wrapper), so observation
        // is skipped for run/shutdown. sync is observed normally.
        let syncResult = try observed.sync()
        #expect(syncResult == 42)

        let entries = log.withLock { $0 }
        #expect(entries == ["before:sync"])
    }

    @Test
    func `Optional nonsending closure unimplemented produces nil`() {
        let api = OptionalNonsendingAPI.unimplemented()
        #expect(api.onComplete == nil)

        #expect(throws: Witness.Unimplemented.Error.self) {
            try api.onEvent(name: "test")
        }
    }

    @Test
    func `Optional nonsending closure can be set and invoked`() async {
        var api = OptionalNonsendingAPI.unimplemented()
        let called = Synchronization.Mutex(false)
        api.onComplete = { called.withLock { $0 = true } }
        await api.onComplete?()
        #expect(called.withLock { $0 })
    }

    @Test
    func `Optional nonsending observe passes through`() async throws(Witness.Unimplemented.Error) {
        let log = Synchronization.Mutex<[String]>([])
        let completeCalled = Synchronization.Mutex(false)
        let base = OptionalNonsendingAPI(
            onEvent: { _ in },
            onComplete: { completeCalled.withLock { $0 = true } }
        )
        let observed = base.observe.before { action in
            log.withLock { $0.append("before:\(action.case)") }
        }

        // onComplete is nonisolated(nonsending) optional — passed through unchanged
        await observed.onComplete?()
        #expect(completeCalled.withLock { $0 })

        // onEvent is a regular @Sendable closure — observation works
        try observed.onEvent(name: "test")
        let entries = log.withLock { $0 }
        #expect(entries == ["before:onEvent"])
    }
}

// MARK: - Observe Tests

extension Witness.Unimplemented.Test.Unit {
    @Test
    func `Observe after receives outcome on success`() async throws {
        let log = Synchronization.Mutex<[String]>([])
        let base = TestAPI(
            fetch: { id in "result-\(id)" },
            update: { _, _ in }
        )
        let observed = base.observe.after { outcome in
            log.withLock { $0.append("after:\(outcome.action.case)") }
        }
        let result = try await observed.fetch(id: 1)
        #expect(result == "result-1")
        let entries = log.withLock { $0 }
        #expect(entries == ["after:fetch"])
    }

    @Test
    func `Observe after receives outcome on failure`() async throws {
        let log = Synchronization.Mutex<[String]>([])
        let base = TestAPI.unimplemented()
        let observed = base.observe.after { outcome in
            log.withLock { $0.append("after:\(outcome.action.case)") }
        }
        await #expect(throws: Witness.Unimplemented.Error.self) {
            _ = try await observed.fetch(id: 1)
        }
        let entries = log.withLock { $0 }
        #expect(entries == ["after:fetch"])
    }

    @Test
    func `Observe both receives before and after`() async throws {
        let log = Synchronization.Mutex<[String]>([])
        let base = TestAPI(
            fetch: { id in "result-\(id)" },
            update: { _, _ in }
        )
        let observed = base.observe(
            { action in log.withLock { $0.append("before:\(action.case)") } },
            after: { outcome in log.withLock { $0.append("after:\(outcome.action.case)") } }
        )
        let result = try await observed.fetch(id: 1)
        #expect(result == "result-1")
        let entries = log.withLock { $0 }
        #expect(entries == ["before:fetch", "after:fetch"])
    }
}

// MARK: - ExistingInitAPI Tests

extension Witness.Unimplemented.Test.Unit {
    @Test
    func `ExistingInitAPI compiles and works with custom init`() throws {
        let api = ExistingInitAPI(fetch: { id in "custom-\(id)" })
        let result = try api.fetch(id: 1)
        #expect(result == "custom-1")
    }

    @Test
    func `ExistingInitAPI unimplemented works`() {
        let api = ExistingInitAPI.unimplemented()
        #expect(throws: Witness.Unimplemented.Error.self) {
            _ = try api.fetch(id: 1)
        }
    }
}

// MARK: - Typed Throws Preservation Tests

extension Witness.Unimplemented.Test.Unit {
    @Test
    func `Generated convenience method preserves typed throws`() async {
        let api = TestAPI.unimplemented()

        // If typed throws is preserved, this do/catch compiles with typed error
        do {
            _ = try await api.fetch(id: 1)
        } catch {
            // error should be Witness.Unimplemented.Error, not any Error
            let _: Witness.Unimplemented.Error = error
            #expect(error.witness == "TestAPI")
        }
    }
}

// MARK: - Nested Type Tests

extension Witness.Unimplemented.Test.Unit {
    @Test
    func `Nested witness struct compiles and works`() throws {
        let client = APINamespace.Client.unimplemented()
        #expect(throws: Witness.Unimplemented.Error.self) {
            _ = try client.fetch(id: 1)
        }

        let observed = APINamespace.Client(fetch: { id in "nested-\(id)" })
            .observe.before { _ in }
        let result = try observed.fetch(id: 1)
        #expect(result == "nested-1")
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
