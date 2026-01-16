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

import Witness_Primitives

extension Witness {
    /// Task-local context for witness dependency injection.
    ///
    /// `Witness.Context` provides scoped witness overrides via Task-local storage.
    /// Use ``with(_:operation:)-7r1dw`` to override witnesses for a scope:
    ///
    /// ```swift
    /// try await Witness.Context.with { values in
    ///     values[FileSystem.self] = .mock
    /// } operation: {
    ///     // FileSystem.self resolves to .mock here
    ///     let data = try await readFile()
    /// }
    /// ```
    ///
    /// ## Accessing Current Values
    ///
    /// Within a scope, access the current witness values:
    ///
    /// ```swift
    /// let fs = Witness.Context.current[FileSystem.self]
    /// ```
    public struct Context: Sendable {
        /// Task-local storage for the current context.
        @TaskLocal
        private static var _current: Context = Context(values: Values())

        /// The witness values in this context.
        public var values: Values

        @usableFromInline
        internal init(values: Values) {
            self.values = values
        }
    }
}

// MARK: - Current Access

extension Witness.Context {
    /// The current witness values for this task.
    ///
    /// Returns the values from the innermost ``with(_:operation:)-7r1dw`` scope,
    /// or the default values if not in a scope.
    public static var current: Witness.Values {
        _current.values
    }
}

// MARK: - Scoped Override (Synchronous)

extension Witness.Context {
    /// Executes a closure with modified witness values.
    ///
    /// Per [API-ERR-003], typed errors are preserved by construction via Result.
    ///
    /// - Parameters:
    ///   - modify: A closure that modifies the witness values for the scope.
    ///   - operation: The operation to execute with the modified values.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    public static func with<T, E: Error>(
        _ modify: (inout Witness.Values) -> Void,
        operation: () throws(E) -> T
    ) throws(E) -> T {
        var context = _current
        modify(&context.values)
        return try $_current.withValue(context) {
            do throws(E) {
                return Result<T, E>.success(try operation())
            } catch {
                return Result<T, E>.failure(error)
            }
        }.get()
    }
}

// MARK: - Scoped Override (Asynchronous)

extension Witness.Context {
    /// Executes an async closure with modified witness values.
    ///
    /// Per [API-ERR-003], typed errors are preserved by construction via Result.
    ///
    /// - Parameters:
    ///   - modify: A closure that modifies the witness values for the scope.
    ///   - operation: The async operation to execute with the modified values.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    public static func with<T, E: Error>(
        _ modify: (inout Witness.Values) -> Void,
        operation: () async throws(E) -> T
    ) async throws(E) -> T {
        var context = _current
        modify(&context.values)
        return try await $_current.withValue(context) {
            do throws(E) {
                return Result<T, E>.success(try await operation())
            } catch {
                return Result<T, E>.failure(error)
            }
        }.get()
    }
}

// MARK: - Test Context

extension Witness.Context {
    /// Executes a closure in a test context.
    ///
    /// In a test context, unset keys return their `testValue` instead of `liveValue`.
    ///
    /// - Parameters:
    ///   - modify: An optional closure to further modify values.
    ///   - operation: The test operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: Rethrows any error from the operation.
    public static func withTest<T>(
        _ modify: ((inout Witness.Values) -> Void)? = nil,
        operation: () async throws -> T
    ) async rethrows -> T {
        var context = _current
        context.values.isTestContext = true
        modify?(&context.values)
        return try await $_current.withValue(context, operation: operation)
    }
}
