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
    /// A container for witness values keyed by their ``Witness/Key`` type.
    ///
    /// Use `Witness.Values` to store and retrieve witnesses in a type-safe manner:
    ///
    /// ```swift
    /// var values = Witness.Values()
    /// values[FileSystem.self] = .mock
    /// let fs = values[FileSystem.self]  // FileSystem
    /// ```
    ///
    /// Values not explicitly set will return their key's `liveValue` or `testValue`
    /// depending on the current context.
    public struct Values: Sendable {
        /// Storage using type identifier as key.
        @usableFromInline
        internal var storage: [ObjectIdentifier: any Sendable]

        /// Whether we're in a test context.
        @usableFromInline
        internal var isTestContext: Bool

        /// Creates an empty values container.
        ///
        /// - Parameter isTestContext: If `true`, unset keys return `testValue` instead of `liveValue`.
        @inlinable
        public init(isTestContext: Bool = false) {
            self.storage = [:]
            self.isTestContext = isTestContext
        }
    }
}

extension Witness.Values {
    /// Accesses the witness for the given key type.
    ///
    /// - Parameter key: The key type identifying the witness.
    /// - Returns: The stored witness, or the key's default value if not set.
    @inlinable
    public subscript<K: Witness.Key>(key: K.Type) -> K.Value {
        get {
            let id = ObjectIdentifier(K.self)
            if let value = storage[id] as? K.Value {
                return value
            }
            return isTestContext ? K.testValue : K.liveValue
        }
        set {
            let id = ObjectIdentifier(K.self)
            storage[id] = newValue
        }
    }
}
