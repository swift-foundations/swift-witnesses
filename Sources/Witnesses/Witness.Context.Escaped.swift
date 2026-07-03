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

extension Witness.Context {
    /// Captures witness context for use in escaping closures.
    ///
    /// Unlike `Async.Continuation` (which resumes suspended computations),
    /// `Escaped` captures witness VALUES to propagate context to escaping closures
    /// like `DispatchQueue.async`, delegate callbacks, or timers.
    ///
    /// ## Example
    ///
    /// ```swift
    /// func setupTimer() {
    ///     Witness.Context.withEscaped { escaped in
    ///         Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    ///             escaped.yield {
    ///                 let logger = Witness.Context.current[Logger.self]
    ///                 logger.log("Timer fired")
    ///             }
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// ## When to Use
    ///
    /// Use `Escaped` when you need witness context in:
    /// - `DispatchQueue.async` or `DispatchQueue.main.async` blocks
    /// - Timer callbacks
    /// - Delegate methods
    /// - Notification observers
    /// - Any closure that outlives the current scope
    public struct Escaped: Sendable {
        @usableFromInline
        internal let values: Witness.Values

        @usableFromInline
        internal let mode: Mode

        @usableFromInline
        internal init() {
            self.values = Witness.Context.current
            self.mode = Witness.Context.currentMode
        }

        /// Execute a synchronous operation with the captured witness context.
        ///
        /// - Parameter operation: The operation to execute.
        /// - Returns: The result of the operation.
        /// - Throws: The typed error from the operation.
        @inlinable
        public func yield<R, E: Swift.Error>(
            _ operation: () throws(E) -> R
        ) throws(E) -> R {
            try Witness.Context.with(mode: mode, { $0 = values }, operation: operation)
        }

        /// Execute an asynchronous operation with the captured witness context.
        ///
        /// - Parameter operation: The async operation to execute.
        /// - Returns: The result of the operation.
        /// - Throws: The typed error from the operation.
        @inlinable
        nonisolated(nonsending)
            public func yield<R, E: Swift.Error>(
                _ operation: nonisolated(nonsending) () async throws(E) -> R
            ) async throws(E) -> R
        {
            try await Witness.Context.with(mode: mode, { $0 = values }, operation: operation)
        }
    }

    /// Capture the current witness context for use in escaping closures.
    ///
    /// - Parameter operation: A closure that receives the captured context.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    @inlinable
    public static func withEscaped<R, E: Swift.Error>(
        _ operation: (Escaped) throws(E) -> R
    ) throws(E) -> R {
        try operation(Escaped())
    }

    /// Capture the current witness context for use in escaping async closures.
    ///
    /// - Parameter operation: An async closure that receives the captured context.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    @inlinable
    public static func withEscaped<R, E: Swift.Error>(
        _ operation: (Escaped) async throws(E) -> R
    ) async throws(E) -> R {
        try await operation(Escaped())
    }
}
