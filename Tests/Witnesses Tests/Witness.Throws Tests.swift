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

// MARK: - Throws-Shape Failure Type Derivation
//
// Regression coverage for the untyped-throws → `Never` conflation bug. Closure
// fields typed bare `throws` / `async throws` previously derived a `Never` failure
// type, emitting `Result<T, Never>.failure(error)` in generated observe code —
// which cannot compile (`any Error` is not convertible to `Never`) and produced
// the mass build failures observed downstream. The fix derives `any Swift.Error`
// for bare throws, the concrete type for typed throws, and `Never` only for
// non-throwing.
//
// Each construction below doubles as a compile-time assertion: the generated
// `ThrowsMatrixAPI.Result.<case>` accepts a `Standard_Library_Extensions.Result`
// with one specific `Failure`, and generic invariance makes passing any other
// failure type a hard type error.

extension Witness.Test.Unit {
    @Test
    func `Untyped throws derives any Error failure type`() throws {
        let error: any Error = CustomError.failed

        // Sync bare `throws` — only compiles if the derived failure is `any Error`.
        let syncResult = ThrowsMatrixAPI.Result.bareSync(
            Standard_Library_Extensions.Result<Int, any Swift.Error>.failure(error)
        )
        switch consume syncResult {
        case .bareSync(.failure(let captured)):
            #expect((captured as? CustomError) == .failed)
        default:
            Issue.record("Expected .bareSync(.failure)")
        }

        // Async bare `throws` — same derivation for the async shape.
        let asyncResult = ThrowsMatrixAPI.Result.bareAsync(
            Standard_Library_Extensions.Result<String, any Swift.Error>.failure(error)
        )
        switch consume asyncResult {
        case .bareAsync(.failure(let captured)):
            #expect((captured as? CustomError) == .failed)
        default:
            Issue.record("Expected .bareAsync(.failure)")
        }
    }

    @Test
    func `Typed throws derives the concrete failure type`() throws {
        // Leading-dot `.failed` resolves only if `Failure` is `CustomError`, and
        // `captured == .failed` compiles only if `captured` is `CustomError`
        // (the erased `any Error` is not Equatable) — pinning the concrete type.
        let syncResult = ThrowsMatrixAPI.Result.typedSync(
            Standard_Library_Extensions.Result<Int, CustomError>.failure(.failed)
        )
        switch consume syncResult {
        case .typedSync(.failure(let captured)):
            #expect(captured == .failed)
        default:
            Issue.record("Expected .typedSync(.failure)")
        }

        let asyncResult = ThrowsMatrixAPI.Result.typedAsync(
            Standard_Library_Extensions.Result<String, CustomError>.failure(.failed)
        )
        switch consume asyncResult {
        case .typedAsync(.failure(let captured)):
            #expect(captured == .failed)
        default:
            Issue.record("Expected .typedAsync(.failure)")
        }
    }

    @Test
    func `Non-throwing derives Never failure type`() throws {
        // Constructing with `Result<Int, Never>` compiles only if the derived
        // failure type is `Never` (not the `any Error` used for bare throws).
        let result = ThrowsMatrixAPI.Result.nonThrowing(
            Standard_Library_Extensions.Result<Int, Never>.success(42)
        )
        switch consume result {
        case .nonThrowing(.success(let value)):
            #expect(value == 42)
        default:
            Issue.record("Expected .nonThrowing(.success)")
        }
    }
}

// MARK: - Observe Codegen (untyped async throws, end-to-end)

extension Witness.Test.Integration {
    @Test
    func `Observe after runs on untyped async throws failure path`() async throws {
        let base = ThrowsMatrixAPI(
            bareSync: { 1 },
            bareAsync: { _ in throw CustomError.failed },
            typedSync: { 2 },
            typedAsync: { _ in "unused" },
            nonThrowing: { 3 }
        )

        // Exercises generateObserveBody's catch-path for an untyped `async throws`
        // field: previously emitted `Result<String, Never>.failure(error)` and
        // failed to compile. The observer must run before the error is rethrown.
        let observedCalls = Synchronization.Mutex<[String]>([])
        let observed = base.observe.after { outcome in
            observedCalls.withLock { $0.append("\(outcome.action.case)") }
        }

        await #expect(throws: CustomError.self) {
            _ = try await observed.bareAsync(id: 7)
        }
        #expect(observedCalls.withLock { $0 } == ["bareAsync"])
    }
}
