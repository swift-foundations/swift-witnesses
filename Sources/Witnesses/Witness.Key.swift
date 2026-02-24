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

// MARK: - Hoisted Protocol (Swift limitation: protocols cannot nest in protocols)

/// A key for test witnesses that don't have a live implementation.
///
/// - Note: This protocol is hoisted to module level due to Swift's limitation
///   on nesting protocols. Use ``Witness/Key/Test`` as the public API.
///
/// `testValue` is **required**. `previewValue` defaults to `testValue`.
public protocol __WitnessKeyTest<Value>: Sendable {
    /// The witness type this key provides.
    associatedtype Value: ~Copyable & Sendable = Self

    /// The default value for test contexts.
    static var testValue: Value { get }

    /// The default value for preview contexts.
    ///
    /// If not implemented, defaults to `testValue`.
    static var previewValue: Value { get }
}

extension __WitnessKeyTest where Value: Copyable {
    /// Default preview value falls back to test value.
    @inlinable
    public static var previewValue: Value { testValue }
}

// MARK: - Witness.Key

extension Witness {
    /// A key for identifying and accessing a witness in a ``Witness/Values`` container.
    ///
    /// Conform to this protocol to register a witness type for dependency injection:
    ///
    /// ```swift
    /// extension FileSystem: Witness.Key {
    ///     public static var liveValue: FileSystem { .darwin }
    /// }
    /// ```
    ///
    /// ## Default Value Chain
    ///
    /// `Witness.Key` inherits from ``Witness/Key/Test``, adding the `liveValue` requirement.
    /// The default value chain is:
    ///
    /// ```
    /// testValue → previewValue → liveValue
    /// ```
    ///
    /// This means:
    /// - `previewValue` defaults to `liveValue`
    /// - `testValue` defaults to `previewValue` (which defaults to `liveValue`)
    ///
    /// If you customize `previewValue`, tests will also get that customization
    /// unless you explicitly override `testValue`.
    public protocol Key<Value>: __WitnessKeyTest {
        /// The default value for production contexts.
        static var liveValue: Value { get }
    }
}

extension Witness.Key where Value: Copyable {
    /// Default preview value falls back to live value.
    @inlinable
    public static var previewValue: Value { liveValue }

    /// Default test value falls back to preview value (which falls back to live value).
    @inlinable
    public static var testValue: Value { previewValue }
}

// MARK: - Witness.Key.Test (typealias)

extension Witness.Key {
    /// A key for test witnesses that don't have a live implementation.
    ///
    /// Use this protocol when you want to separate a witness's interface from its
    /// live implementation. The interface module conforms to ``Test``, while the
    /// implementation module adds ``Key`` conformance.
    ///
    /// ```swift
    /// // In the interface module:
    /// extension APIClient: Witness.Key.Test {
    ///     public static var testValue: APIClient { .mock }
    /// }
    ///
    /// // In the implementation module:
    /// extension APIClient: Witness.Key {
    ///     public static var liveValue: APIClient { .live }
    /// }
    /// ```
    public typealias Test = __WitnessKeyTest
}
