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

extension Witness.Resolution {
    /// TaskLocal resolution stack for cycle detection.
    ///
    /// Tracks which witnesses are currently being resolved to detect
    /// circular dependencies.
    ///
    /// ## Design
    ///
    /// Per [API-IMPL-010] (no hidden global mutable storage), this uses
    /// `@TaskLocal` rather than a global mutex. The stack is scoped to
    /// the current task and automatically cleaned up.
    ///
    /// ## Usage
    ///
    /// Use ``withPushed(_:mode:operation:)`` to track resolution:
    ///
    /// ```swift
    /// let result = Stack.withPushed(MyKey.self, mode: .live) {
    ///     // Resolve MyKey.Value...
    ///     return .success(value)
    /// }
    /// ```
    ///
    /// If the same key is already on the stack, returns `.failure(.cycle(...))`.
    public struct Stack: Sendable {
        /// TaskLocal storage for the current resolution stack.
        @TaskLocal
        public static var current: Stack = Stack()

        /// The key identifiers currently being resolved.
        @usableFromInline
        internal var keys: [ObjectIdentifier]

        /// Creates an empty resolution stack.
        @usableFromInline
        internal init(keys: [ObjectIdentifier] = []) {
            self.keys = keys
        }

        /// Executes an operation with the given key pushed onto the resolution stack.
        ///
        /// If the key is already on the stack (cycle detected), returns
        /// `.failure(.cycle(...))` without executing the operation.
        ///
        /// ## Scoped API
        ///
        /// This is a scoped API - no manual push/pop. The stack is automatically
        /// restored when the operation completes.
        ///
        /// - Parameters:
        ///   - key: The key type being resolved.
        ///   - mode: The current execution mode (for trace information).
        ///   - operation: The operation to execute with the key on the stack.
        /// - Returns: The result of the operation, or a cycle error.
        @inlinable
        public static func withPushed<K: Witness.Key, T>(
            _ key: K.Type,
            mode: Witness.Context.Mode,
            operation: () -> Result<T, Witness.Resolution.Error>
        ) -> Result<T, Witness.Resolution.Error> {
            let id = ObjectIdentifier(key)
            var stack = current

            // Check for cycle
            if stack.keys.contains(id) {
                let trace = Trace(stack: stack.keys + [id], mode: mode)
                return .failure(.cycle(trace: trace))
            }

            // Push key and execute operation
            stack.keys.append(id)
            return $current.withValue(stack) {
                operation()
            }
        }

        /// Executes an async operation with the given key pushed onto the resolution stack.
        ///
        /// If the key is already on the stack (cycle detected), returns
        /// `.failure(.cycle(...))` without executing the operation.
        ///
        /// - Parameters:
        ///   - key: The key type being resolved.
        ///   - mode: The current execution mode (for trace information).
        ///   - operation: The async operation to execute with the key on the stack.
        /// - Returns: The result of the operation, or a cycle error.
        @inlinable
        nonisolated(nonsending)
        public static func withPushed<K: Witness.Key, T>(
            _ key: K.Type,
            mode: Witness.Context.Mode,
            operation: nonisolated(nonsending) () async -> Result<T, Witness.Resolution.Error>
        ) async -> Result<T, Witness.Resolution.Error> {
            let id = ObjectIdentifier(key)
            var stack = current

            // Check for cycle
            if stack.keys.contains(id) {
                let trace = Trace(stack: stack.keys + [id], mode: mode)
                return .failure(.cycle(trace: trace))
            }

            // Push key and execute operation
            stack.keys.append(id)
            return await $current.withValue(stack) {
                await operation()
            }
        }
    }
}
