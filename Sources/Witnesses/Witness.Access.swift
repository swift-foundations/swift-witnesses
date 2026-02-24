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
    /// A property wrapper that provides access to a witness from the current context.
    ///
    /// Use `@Witness.Access` to declare witness dependencies in your types:
    ///
    /// ```swift
    /// struct FeatureModel {
    ///     @Witness.Access(APIClient.self) var apiClient
    ///     @Witness.Access(FileSystem.self) var fileSystem
    ///
    ///     func loadData() async throws -> Data {
    ///         try await apiClient.fetch(id: 1)
    ///     }
    /// }
    /// ```
    ///
    /// The witness value is resolved from `Witness.Context.current` each time it's accessed,
    /// combined with any values captured at initialization time. This allows the same model
    /// instance to use different implementations when accessed from different scopes.
    ///
    /// ## Context Capture
    ///
    /// The property wrapper captures the context values at initialization time and merges
    /// them with the current context when accessed. This means:
    /// - Values set in the context when the property wrapper was created are preserved
    /// - Values set in nested `Witness.Context.with` blocks override captured values
    @propertyWrapper
    public struct Access<Key: Witness.Key>: Sendable where Key.Value == Key, Key.Value: Copyable {
        @usableFromInline
        internal let initialValues: Witness.Values

        @usableFromInline
        internal let fileID: StaticString

        @usableFromInline
        internal let line: UInt

        /// Creates an access property wrapper for the given witness key.
        ///
        /// - Parameters:
        ///   - key: The witness key type to access.
        ///   - fileID: The source file (for diagnostics).
        ///   - line: The source line (for diagnostics).
        @inlinable
        public init(
            _ key: Key.Type,
            fileID: StaticString = #fileID,
            line: UInt = #line
        ) {
            self.initialValues = Witness.Context.current
            self.fileID = fileID
            self.line = line
        }

        /// The witness value from the current context.
        @inlinable
        public var wrappedValue: Key.Value {
            let merged = initialValues.merging(Witness.Context.current)
            return merged[Key.self]
        }
    }
}
