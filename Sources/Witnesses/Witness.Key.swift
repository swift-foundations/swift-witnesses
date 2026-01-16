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
    /// A key for identifying and accessing a witness in a ``Witness/Values`` container.
    ///
    /// Conform to this protocol to register a witness type for dependency injection:
    ///
    /// ```swift
    /// extension FileSystem: Witness.Key {
    ///     public static var liveValue: FileSystem { .darwin }
    ///     public static var testValue: FileSystem { .mock }
    /// }
    /// ```
    ///
    /// The `liveValue` is used in production contexts, while `testValue` provides
    /// a default for test contexts.
    public protocol Key<Value>: Sendable {
        /// The witness type this key provides.
        associatedtype Value: Sendable

        /// The default value for production contexts.
        static var liveValue: Value { get }

        /// The default value for test contexts.
        ///
        /// If not implemented, defaults to `liveValue`.
        static var testValue: Value { get }
    }
}

extension Witness.Key {
    /// Default test value falls back to live value.
    @inlinable
    public static var testValue: Value { liveValue }
}
