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
    /// A move-only scope token that ensures witness context is used exactly once.
    ///
    /// `Witness.Scope` provides compile-time enforcement that a captured witness
    /// context is consumed. This prevents accidentally dropping context without
    /// using it.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let scope = Witness.Scope(values: customValues)
    /// // ... later ...
    /// let result = scope.run {
    ///     // Operations here use the captured values
    ///     try await processData()
    /// }
    /// ```
    ///
    /// ## Linear Usage Enforcement
    ///
    /// The `consuming` keyword ensures the scope can only be used once at compile time.
    /// The `deinit` precondition catches the edge case where a scope is dropped without
    /// being consumed (e.g., assigned to `_` or stored but never used).
    ///
    /// ```swift
    /// let scope = Witness.Scope(values: values)
    /// _ = scope  // Runtime error: Witness.Scope was never used
    /// ```
    public struct Scope: ~Copyable, Sendable {
        @usableFromInline
        internal var values: Witness.Values

        @usableFromInline
        internal var consumed: Bool = false

        /// Creates a scope with the given witness values.
        ///
        /// - Parameter values: The witness values to use when the scope is run.
        @inlinable
        public init(values: Witness.Values) {
            self.values = values
        }

        /// Creates a scope capturing the current witness context.
        @inlinable
        public init() {
            self.values = Witness.Context.current
        }

        /// Executes a synchronous operation with the captured witness context.
        ///
        /// This method consumes the scope, ensuring it can only be used once.
        ///
        /// - Parameter operation: The operation to execute.
        /// - Returns: The result of the operation.
        /// - Throws: The typed error from the operation.
        @inlinable
        public consuming func run<R, E: Swift.Error>(
            _ operation: () throws(E) -> R
        ) throws(E) -> R {
            consumed = true
            return try Witness.Context.with({ $0 = values }, operation: operation)
        }

        /// Executes an asynchronous operation with the captured witness context.
        ///
        /// This method consumes the scope, ensuring it can only be used once.
        ///
        /// - Parameter operation: The async operation to execute.
        /// - Returns: The result of the operation.
        /// - Throws: The typed error from the operation.
        @inlinable
        nonisolated(nonsending)
            public consuming func run<R, E: Swift.Error>(
                _ operation: nonisolated(nonsending) () async throws(E) -> R
            ) async throws(E) -> R
        {
            consumed = true
            return try await Witness.Context.with({ $0 = values }, operation: operation)
        }

        deinit {
            precondition(consumed, "Witness.Scope was never used. Call run(_:) to execute with the captured context.")
        }
    }
}
