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
import Synchronization

extension Witness {
    /// Namespace for one-time witness preparation infrastructure.
    ///
    /// Use `Witness.Preparation` to configure witnesses globally before first access.
    /// This is useful for app startup where you want to set up live implementations
    /// once and have them available throughout the app lifecycle.
    ///
    /// ## Example
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     init() {
    ///         Witness.Preparation.prepare { values in
    ///             values[APIClient.self] = .live(baseURL: configuration.apiURL)
    ///             values[Database.self] = .sqlite(path: configuration.dbPath)
    ///             values[Logger.self] = .osLog
    ///         }
    ///     }
    ///
    ///     var body: some Scene { ... }
    /// }
    /// ```
    ///
    /// ## Notes
    ///
    /// - `prepare` can only be called once; subsequent calls will trigger a precondition failure
    /// - Prepared values are used as defaults when not overridden by `Witness.Context.with`
    /// - For scoped overrides, use `Witness.Context.with` or `withWitnesses` instead
    public enum Preparation {
        /// Thread-safe storage for prepared values.
        private static let _storage = Mutex<Witness.Values?>(nil)

        /// Prepare witnesses globally (one-time, before first access).
        ///
        /// - Parameter configure: A closure that configures the witness values.
        public static func prepare(
            _ configure: (inout Witness.Values) -> Void
        ) {
            _storage.withLock { stored in
                precondition(stored == nil, "Witnesses already prepared. Witness.Preparation.prepare can only be called once.")
                var values = Witness.Values()
                configure(&values)
                stored = values
            }
        }

        /// Returns the prepared values, if any.
        public static var values: Witness.Values? {
            _storage.withLock { $0 }
        }
    }
}
