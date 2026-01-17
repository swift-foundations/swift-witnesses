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
    /// Namespace for witness preparation infrastructure.
    ///
    /// Use `Witness.Preparation` to configure witnesses for a scope before first access.
    /// This is useful for app startup where you want to set up live implementations
    /// and have them available throughout the operation.
    ///
    /// ## Design
    ///
    /// Per [API-IMPL-010] (no hidden global mutable storage), this uses `@TaskLocal`
    /// rather than a global `Mutex`. The store is scoped to the current task tree
    /// and automatically cleaned up.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// await Witness.Preparation.with { store in
    ///     store.set(APIClient.self, value: .live(baseURL: configuration.apiURL))
    ///     store.set(Database.self, value: .sqlite(path: configuration.dbPath))
    /// } operation: {
    ///     // Within this scope, these values are available
    ///     let client = Witness.Context[APIClient.self]
    /// }
    /// ```
    ///
    /// ## Notes
    ///
    /// - Prepared values are available within the scope and inherited by child tasks
    /// - Scoped API per [API-IMPL-010] - no global one-shot mutation
    /// - For explicit overrides, use `Witness.Context.with` or `withWitnesses` instead
    public enum Preparation {
        /// TaskLocal storage for the current preparation store.
        @TaskLocal
        internal static var store: Store?

        /// The current preparation store, if any.
        public static var current: Store? {
            store
        }
    }
}

// MARK: - Scoped API

extension Witness.Preparation {
    /// Executes an operation with prepared witness values.
    ///
    /// The store is available within the scope and to all child tasks.
    /// Values set in the store are used as fallbacks when resolving witnesses.
    ///
    /// - Parameters:
    ///   - configure: A closure that configures the preparation store.
    ///   - operation: The operation to execute with prepared values.
    /// - Returns: The result of the operation.
    /// - Throws: Rethrows any error from the operation.
    public static func with<T>(
        _ configure: (Store) -> Void,
        operation: () async throws -> T
    ) async rethrows -> T {
        let newStore = Store()
        configure(newStore)
        return try await $store.withValue(newStore, operation: operation)
    }

    /// Executes an operation with prepared witness values (synchronous).
    ///
    /// - Parameters:
    ///   - configure: A closure that configures the preparation store.
    ///   - operation: The operation to execute with prepared values.
    /// - Returns: The result of the operation.
    /// - Throws: Rethrows any error from the operation.
    public static func with<T>(
        _ configure: (Store) -> Void,
        operation: () throws -> T
    ) rethrows -> T {
        let newStore = Store()
        configure(newStore)
        return try $store.withValue(newStore, operation: operation)
    }
}
