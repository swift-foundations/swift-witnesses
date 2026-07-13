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

public import Dependency_Primitives
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
    /// ## Execution Mode
    ///
    /// Per [API-IMPL-002], mode is a state machine enum rather than a boolean.
    /// Use mode-aware context methods:
    ///
    /// ```swift
    /// Witness.Context.with(mode: .test) { values in
    ///     // values now resolve to testValue by default
    /// } operation: {
    ///     // ...
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
        /// The witness values in this context.
        public var values: Values

        /// The execution mode for this context.
        ///
        /// Determines which default value is used when a key is not
        /// explicitly overridden:
        /// - `.live`: Uses `liveValue`
        /// - `.preview`: Uses `previewValue`
        /// - `.test`: Uses `testValue`
        public var mode: Mode

        @usableFromInline
        internal init(values: Values, mode: Mode) {
            self.values = values
            self.mode = mode
        }
    }
}

// MARK: - Context Key

extension Witness.Context {
    /// Internal key for storing `Witness.Context` in L1's dependency dictionary.
    ///
    /// Both `liveValue` and `testValue` return the same default context.
    /// Mode is managed explicitly by ``_withScope(mode:_:operation:)-5f2ep``,
    /// not by L1's `isTestContext` default chain.
    @usableFromInline
    internal enum _ContextKey: Dependency.Key {}

    /// Current context read from L1's dependency dictionary.
    private static var _current: Witness.Context {
        Dependency.Scope.current[_ContextKey.self]
    }
}

extension Witness.Context._ContextKey {
    @usableFromInline
    static var liveValue: Witness.Context {
        Witness.Context(values: .init(), mode: .live)
    }

    @usableFromInline
    static var testValue: Witness.Context { liveValue }
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

    /// The current execution mode for this task.
    ///
    /// Returns the mode from the innermost scope, or `.live` if not in a scope.
    public static var currentMode: Mode {
        _current.mode
    }
}

// MARK: - Value Access (Total API)

extension Witness.Context {
    /// Gets the current value for a key, with explicit mode.
    ///
    /// This is a convenience method that uses the current context's mode.
    ///
    /// - Parameter key: The key type to look up.
    /// - Returns: The resolved value for the key.
    public static subscript<K: Witness.Key>(key: K.Type) -> K.Value where K.Value: Copyable {
        _current.values.value(for: key, mode: _current.mode)
    }

    /// Gets the current value for a test-only key.
    ///
    /// Resolves via the current context's mode. Test-only keys provide no
    /// `liveValue`; `.live` mode falls back to `testValue` — LOUDLY, via
    /// ``Witness/Diagnostics/testDefaultServedInLive(_:)`` (DEBUG traps;
    /// RELEASE reports once per key and serves the default;
    /// `DEPENDENCIES_STRICT=1` traps in release).
    ///
    /// - Note: When `K` also conforms to `Witness.Key`, the more specific
    ///   `Witness.Key` subscript is selected by overload resolution.
    ///
    /// - Parameter key: The test key type to look up.
    /// - Returns: The resolved value for the key.
    public static subscript<K: Witness.Key.Test>(key: K.Type) -> K.Value where K.Value: Copyable {
        _current.values.value(for: key, mode: _current.mode)
    }

    /// Gets the current value for an L1-only dependency key.
    ///
    /// Delegates to `Witness.Values`'s L1-key subscript, which checks
    /// own storage first, then falls back to L1's `Dependency.Scope.current`.
    ///
    /// - Note: When `K` also conforms to `Witness.Key`, the more specific
    ///   `Witness.Key` subscript is selected by overload resolution.
    public static subscript<K: Dependency.Key>(key: K.Type) -> K.Value where K.Value: Copyable {
        _current.values[K.self]
    }

    /// Gets the value for a key with full resolution (total API).
    ///
    /// Per [API-IMPL-003], this returns a `Result` rather than throwing or trapping.
    /// Currently returns `.success` always since basic lookup cannot fail.
    /// Future: will integrate cycle detection via `Resolution.Stack`.
    ///
    /// - Parameter key: The key type to resolve.
    /// - Returns: A result containing the resolved value or a resolution error.
    public static func value<K: Witness.Key>(_ key: K.Type) -> Result<K.Value, Witness.Resolution.Error> where K.Value: Copyable {
        .success(_current.values.value(for: key, mode: _current.mode))
    }

    /// Accesses the current value for a key via closure-scoped borrow.
    ///
    /// Works for all value types including `~Copyable`.
    ///
    /// - Parameters:
    ///   - key: The key type to look up.
    ///   - body: A closure that receives a borrow of the resolved value.
    /// - Returns: The result of `body`.
    public static func withValue<K: Witness.Key, R>(
        _ key: K.Type,
        _ body: (borrowing K.Value) -> R
    ) -> R {
        _current.values.withValue(for: key, mode: _current.mode, body)
    }
}

// MARK: - Scope Bridge

extension Witness.Context {
    /// Infrastructure: single-push scope through L1's `@TaskLocal`.
    ///
    /// Routes all scoping through `Dependency.Scope.with`, storing the
    /// witness context in L1's dictionary under an internal key. This
    /// eliminates the need for a separate `@TaskLocal` in L3.
    ///
    /// The context key is reserved infrastructure and is overwritten
    /// after `modify` returns. User L1-key writes via the second
    /// `inout` parameter are preserved.
    ///
    /// - Parameters:
    ///   - mode: Optional mode override. When non-nil, sets both
    ///     `context.mode` and `l1Values.isTestContext`.
    ///   - modify: A closure receiving witness values and L1 values
    ///     for modification.
    ///   - operation: The operation to execute in the new scope.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    @inlinable
    public static func _withScope<T, E: Swift.Error>(
        mode: Mode? = nil,
        _ modify: (inout Witness.Values, inout Dependency_Primitives.Dependency.Values) -> Void,
        operation: () throws(E) -> T
    ) throws(E) -> T {
        try Dependency.Scope.with(
            { l1Values in
                var context = l1Values[_ContextKey.self]
                if let mode {
                    context.mode = mode
                    l1Values.isTestContext = (mode == .test)
                }
                modify(&context.values, &l1Values)
                l1Values[_ContextKey.self] = context
            },
            operation: operation
        )
    }

    /// Async variant of ``_withScope(mode:_:operation:)-5f2ep``.
    ///
    /// - Parameters:
    ///   - mode: Optional mode override.
    ///   - modify: A closure receiving witness values and L1 values
    ///     for modification.
    ///   - operation: The async operation to execute in the new scope.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    @inlinable
    nonisolated(nonsending)
        public static func _withScope<T, E: Swift.Error>(
            mode: Mode? = nil,
            _ modify: (inout Witness.Values, inout Dependency_Primitives.Dependency.Values) -> Void,
            operation: nonisolated(nonsending) () async throws(E) -> T
        ) async throws(E) -> T
    {
        try await Dependency.Scope.with(
            { l1Values in
                var context = l1Values[_ContextKey.self]
                if let mode {
                    context.mode = mode
                    l1Values.isTestContext = (mode == .test)
                }
                modify(&context.values, &l1Values)
                l1Values[_ContextKey.self] = context
            },
            operation: operation
        )
    }
}

// MARK: - Scoped Override (Synchronous)

extension Witness.Context {
    /// Executes a closure with modified witness values.
    ///
    /// Per [API-ERR-003], typed errors are preserved by construction.
    ///
    /// - Parameters:
    ///   - modify: A closure that modifies the witness values for the scope.
    ///   - operation: The operation to execute with the modified values.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    public static func with<T, E: Swift.Error>(
        _ modify: (inout Witness.Values) -> Void,
        operation: () throws(E) -> T
    ) throws(E) -> T {
        try _withScope(
            { witnessValues, _ in
                modify(&witnessValues)
            },
            operation: operation
        )
    }

    /// Executes a closure with modified witness values and mode.
    ///
    /// - Parameters:
    ///   - mode: The execution mode for the scope.
    ///   - modify: A closure that modifies the witness values for the scope.
    ///   - operation: The operation to execute with the modified values.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    public static func with<T, E: Swift.Error>(
        mode: Mode,
        _ modify: ((inout Witness.Values) -> Void)? = nil,
        operation: () throws(E) -> T
    ) throws(E) -> T {
        try _withScope(
            mode: mode,
            { witnessValues, _ in
                modify?(&witnessValues)
            },
            operation: operation
        )
    }
}

// MARK: - Scoped Override (Asynchronous)

extension Witness.Context {
    /// Executes an async closure with modified witness values.
    ///
    /// This overload preserves actor isolation, allowing the operation to run
    /// in the caller's isolation context.
    ///
    /// Per [API-ERR-003], typed errors are preserved by construction.
    ///
    /// - Parameters:
    ///   - modify: A closure that modifies the witness values for the scope.
    ///   - operation: The async operation to execute with the modified values.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    nonisolated(nonsending)
        public static func with<T, E: Swift.Error>(
            _ modify: (inout Witness.Values) -> Void,
            operation: nonisolated(nonsending) () async throws(E) -> T
        ) async throws(E) -> T
    {
        try await _withScope(
            { witnessValues, _ in
                modify(&witnessValues)
            },
            operation: operation
        )
    }

    /// Executes an async closure with modified witness values and mode.
    ///
    /// - Parameters:
    ///   - mode: The execution mode for the scope.
    ///   - modify: A closure that modifies the witness values for the scope.
    ///   - operation: The async operation to execute with the modified values.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    nonisolated(nonsending)
        public static func with<T, E: Swift.Error>(
            mode: Mode,
            _ modify: ((inout Witness.Values) -> Void)? = nil,
            operation: nonisolated(nonsending) () async throws(E) -> T
        ) async throws(E) -> T
    {
        try await _withScope(
            mode: mode,
            { witnessValues, _ in
                modify?(&witnessValues)
            },
            operation: operation
        )
    }
}

// MARK: - Mode-Specific Contexts (Synchronous)

extension Witness.Context {
    /// Executes a synchronous closure in test mode.
    ///
    /// In test mode, unset keys return their `testValue`.
    ///
    /// - Parameters:
    ///   - modify: An optional closure to further modify values.
    ///   - operation: The test operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    public static func withTest<T, E: Swift.Error>(
        _ modify: ((inout Witness.Values) -> Void)? = nil,
        operation: () throws(E) -> T
    ) throws(E) -> T {
        try _withScope(
            mode: .test,
            { witnessValues, _ in
                modify?(&witnessValues)
            },
            operation: operation
        )
    }

    /// Executes a synchronous closure in preview mode.
    ///
    /// In preview mode, unset keys return their `previewValue`.
    ///
    /// - Parameters:
    ///   - modify: An optional closure to further modify values.
    ///   - operation: The preview operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    public static func withPreview<T, E: Swift.Error>(
        _ modify: ((inout Witness.Values) -> Void)? = nil,
        operation: () throws(E) -> T
    ) throws(E) -> T {
        try _withScope(
            mode: .preview,
            { witnessValues, _ in
                modify?(&witnessValues)
            },
            operation: operation
        )
    }
}

// MARK: - Mode-Specific Contexts (Asynchronous)

extension Witness.Context {
    /// Executes an async closure in test mode.
    ///
    /// In test mode, unset keys return their `testValue`.
    ///
    /// - Parameters:
    ///   - modify: An optional closure to further modify values.
    ///   - operation: The test operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    nonisolated(nonsending)
        public static func withTest<T, E: Swift.Error>(
            _ modify: ((inout Witness.Values) -> Void)? = nil,
            operation: nonisolated(nonsending) () async throws(E) -> T
        ) async throws(E) -> T
    {
        try await _withScope(
            mode: .test,
            { witnessValues, _ in
                modify?(&witnessValues)
            },
            operation: operation
        )
    }

    /// Executes an async closure in preview mode.
    ///
    /// In preview mode, unset keys return their `previewValue`.
    ///
    /// - Parameters:
    ///   - modify: An optional closure to further modify values.
    ///   - operation: The preview operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    nonisolated(nonsending)
        public static func withPreview<T, E: Swift.Error>(
            _ modify: ((inout Witness.Values) -> Void)? = nil,
            operation: nonisolated(nonsending) () async throws(E) -> T
        ) async throws(E) -> T
    {
        try await _withScope(
            mode: .preview,
            { witnessValues, _ in
                modify?(&witnessValues)
            },
            operation: operation
        )
    }
}
