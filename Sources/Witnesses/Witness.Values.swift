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
public import Ownership_Primitives
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
    /// ## Lookup Order
    ///
    /// When accessing a value, the lookup order is:
    /// 1. Explicit overrides (stored in `_storage`)
    /// 2. Prepared values (from `Witness.Preparation.Store`)
    /// 3. Default value (based on mode: `liveValue`, `previewValue`, or `testValue`)
    ///
    /// ## Mode
    ///
    /// The execution mode is now part of ``Witness/Context`` rather than `Values`.
    /// Per [API-IMPL-002], mode is a state machine enum rather than a boolean.
    public struct Values: Sendable {
        /// Storage for explicit overrides using type identifier as key with UnsafeRawPointer values.
        @usableFromInline
        internal var _storage: _Storage

        /// Reference to prepared values store.
        @usableFromInline
        internal var _preparedRef: Witness.Preparation.Store?

        /// Creates an empty values container.
        @inlinable
        public init() {
            self._storage = _Storage()
            self._preparedRef = nil
        }

        /// Creates a values container with a reference to prepared values.
        ///
        /// - Parameter preparedStore: The preparation store to use for lookups.
        @usableFromInline
        internal init(preparedStore: Witness.Preparation.Store?) {
            self._storage = _Storage()
            self._preparedRef = preparedStore
        }
    }
}

extension Witness.Values {
    // WHY: Category D — structural Sendable workaround (SP-5) per [MEM-SAFE-024].
    // WHY: UnsafeRawPointer in the dictionary blocks structural Sendable inference.
    // WHY: No caller invariant to uphold — COW discipline at the Values layer
    // WHY: ensures each isolation domain owns its unique _Storage after first write.
    // WHY: Encapsulation invariant per [MEM-SAFE-021] — `_Storage` is
    // WHY: `@usableFromInline` but its raw-pointer storage is internal-only;
    // WHY: consumers see only the type-safe `Values` surface.
    // WHEN TO REMOVE: When compiler gains structural Sendable inference through
    // WHEN TO REMOVE: UnsafeRawPointer-backed Copyable containers.
    // TRACKING: unsafe-audit-findings.md Category D; SP-5.
    /// Internal storage with proper memory cleanup.
    /// Uses UnsafeRawPointer to avoid existential overhead (8 bytes vs 40 bytes per entry).
    @usableFromInline
    final class _Storage: @unchecked Sendable {
        @usableFromInline
        var dict: [ObjectIdentifier: UnsafeRawPointer]

        @usableFromInline
        init() {
            unsafe (self.dict = [:])
        }

        /// Releases all retained boxes on deallocation.
        deinit {
            var iter = unsafe dict.values.makeIterator()
            while let ptr = unsafe iter.next() {
                unsafe Unmanaged<AnyObject>.fromOpaque(ptr).release()
            }
        }
    }
}

extension Witness.Values {
    /// Ensures unique storage for mutation (Copy-on-Write).
    @inlinable
    package mutating func _ensureUnique() {
        if !isKnownUniquelyReferenced(&_storage) {
            let newStorage = _Storage()
            // Copy all entries (retaining each box)
            var iter = unsafe _storage.dict.makeIterator()
            while let (key, ptr) = unsafe iter.next() {
                _ = unsafe Unmanaged<AnyObject>.fromOpaque(ptr).retain()
                unsafe newStorage.set(ptr, for: key)
            }
            _storage = newStorage
        }
    }

    /// Accesses the witness for the given key type using the specified mode.
    ///
    /// This internal method performs the lookup with explicit mode.
    ///
    /// - Parameters:
    ///   - key: The key type identifying the witness.
    ///   - mode: The execution mode determining default value selection.
    /// - Returns: The stored witness, or the key's default value based on mode.
    @usableFromInline
    internal func value<K: Witness.Key>(for key: K.Type, mode: Witness.Context.Mode) -> K.Value where K.Value: Copyable {
        let id = ObjectIdentifier(K.self)

        // 1. Check explicit overrides
        if let ptr = unsafe _storage.dict[id] {
            return unsafe Unmanaged<Ownership.Immutable<K.Value>>.fromOpaque(ptr)
                .takeUnretainedValue()
                .value
        }

        // 2. Check prepared values
        if let prepared = _preparedRef?.get(K.self) {
            return prepared
        }

        // 3. Return default based on mode
        switch mode {
        case .live:
            return K.liveValue

        case .preview:
            return K.previewValue

        case .test:
            return K.testValue
        }
    }

    /// Accesses the witness for a test-only key type using the specified mode.
    ///
    /// Mirrors ``value(for:mode:)`` for keys that provide only `testValue`
    /// (and an optional `previewValue`) without a `liveValue`. Because no live
    /// implementation exists, `.live` mode resolves to `testValue`.
    ///
    /// - Parameters:
    ///   - key: The test key type identifying the witness.
    ///   - mode: The execution mode determining default value selection.
    /// - Returns: The stored witness, or the key's default value based on mode.
    @usableFromInline
    internal func value<K: Witness.Key.Test>(for key: K.Type, mode: Witness.Context.Mode) -> K.Value where K.Value: Copyable {
        let id = ObjectIdentifier(K.self)

        // 1. Check explicit overrides
        if let ptr = unsafe _storage.dict[id] {
            return unsafe Unmanaged<Ownership.Immutable<K.Value>>.fromOpaque(ptr)
                .takeUnretainedValue()
                .value
        }

        // 2. Check prepared values
        if let prepared = _preparedRef?.get(K.self) {
            return prepared
        }

        // 3. Return default based on mode (no liveValue for test-only keys)
        switch mode {
        case .live, .test:
            return K.testValue

        case .preview:
            return K.previewValue
        }
    }

    /// Accesses the witness for the given key type via closure-scoped borrow.
    ///
    /// Works for all value types including `~Copyable`. Handles all three lookup
    /// stages (stored, prepared, default) and calls `body` directly per-branch.
    ///
    /// - Parameters:
    ///   - key: The key type identifying the witness.
    ///   - mode: The execution mode determining default value selection.
    ///   - body: A closure that receives a borrow of the resolved value.
    /// - Returns: The result of `body`.
    @usableFromInline
    internal func withValue<K: Witness.Key, R>(
        for key: K.Type,
        mode: Witness.Context.Mode,
        _ body: (borrowing K.Value) -> R
    ) -> R {
        let id = ObjectIdentifier(K.self)

        // 1. Check explicit overrides
        if let ptr = unsafe _storage.dict[id] {
            return body(
                unsafe Unmanaged<Ownership.Immutable<K.Value>>.fromOpaque(ptr)
                    .takeUnretainedValue()
                    .value
            )
        }

        // 2. Check prepared values
        if let result = _preparedRef?.withValue(K.self, body) {
            return result
        }

        // 3. Return default based on mode
        return switch mode {
        case .live: body(K.liveValue)
        case .preview: body(K.previewValue)
        case .test: body(K.testValue)
        }
    }

    /// Accesses the witness for the given key type.
    ///
    /// For get operations, uses `.live` mode by default. For mode-aware access,
    /// use ``Witness/Context`` which provides the current mode.
    ///
    /// - Parameter key: The key type identifying the witness.
    /// - Returns: The stored witness, or the key's `liveValue` if not set.
    @inlinable
    public subscript<K: Witness.Key>(key: K.Type) -> K.Value where K.Value: Copyable {
        get {
            value(for: key, mode: .live)
        }
        set {
            _ensureUnique()
            let id = ObjectIdentifier(K.self)
            // Release old value if present
            if let oldPtr = unsafe _storage.dict[id] {
                unsafe Unmanaged<AnyObject>.fromOpaque(oldPtr).release()
            }
            // Store new value (retained)
            let box = Ownership.Immutable(newValue)
            let ptr = unsafe UnsafeRawPointer(Unmanaged.passRetained(box).toOpaque())
            unsafe _storage.set(ptr, for: id)
        }
    }

    /// Accesses the witness for a test-only key type.
    ///
    /// For keys that provide only `testValue` (per ``Witness/Key/Test``), the
    /// getter resolves in `.test` mode; there is no `liveValue` fallback. The
    /// setter stores an explicit override, consistent with the `Witness.Key`
    /// subscript.
    ///
    /// - Note: When `K` also conforms to `Witness.Key`, the more specific
    ///   `Witness.Key` subscript is selected by overload resolution.
    ///
    /// - Parameter key: The test key type identifying the witness.
    /// - Returns: The stored witness, or the key's `testValue` if not set.
    @inlinable
    public subscript<K: Witness.Key.Test>(key: K.Type) -> K.Value where K.Value: Copyable {
        get {
            value(for: key, mode: .test)
        }
        set {
            _ensureUnique()
            let id = ObjectIdentifier(K.self)
            // Release old value if present
            if let oldPtr = unsafe _storage.dict[id] {
                unsafe Unmanaged<AnyObject>.fromOpaque(oldPtr).release()
            }
            // Store new value (retained)
            let box = Ownership.Immutable(newValue)
            let ptr = unsafe UnsafeRawPointer(Unmanaged.passRetained(box).toOpaque())
            unsafe _storage.set(ptr, for: id)
        }
    }

    /// Accesses the value for an L1-only dependency key.
    ///
    /// For get operations, checks own storage first, then falls back to
    /// L1's `Dependency.Scope.current`. For set operations, stores the value
    /// in this container (consistent with `Witness.Key` behavior).
    ///
    /// - Note: When `K` also conforms to `Witness.Key`, the more specific
    ///   `Witness.Key` subscript is selected by overload resolution.
    @inlinable
    public subscript<K: Dependency.Key>(key: K.Type) -> K.Value where K.Value: Copyable {
        get {
            let id = ObjectIdentifier(K.self)
            if let ptr = unsafe _storage.dict[id] {
                return unsafe Unmanaged<Ownership.Immutable<K.Value>>.fromOpaque(ptr)
                    .takeUnretainedValue()
                    .value
            }
            return Dependency.Scope.current[K.self]
        }
        set {
            _ensureUnique()
            let id = ObjectIdentifier(K.self)
            if let oldPtr = unsafe _storage.dict[id] {
                unsafe Unmanaged<AnyObject>.fromOpaque(oldPtr).release()
            }
            let box = Ownership.Immutable(newValue)
            let ptr = unsafe UnsafeRawPointer(Unmanaged.passRetained(box).toOpaque())
            unsafe _storage.set(ptr, for: id)
        }
    }

    /// Sets the witness for the given key type.
    ///
    /// Works for all value types including `~Copyable`. Takes ownership of the
    /// value and stores it in the container.
    ///
    /// - Parameters:
    ///   - key: The key type identifying the witness.
    ///   - value: The value to store (consumed).
    public mutating func set<K: Witness.Key>(_ key: K.Type, _ value: consuming K.Value) {
        _ensureUnique()
        let id = ObjectIdentifier(K.self)
        // Release old value if present
        if let oldPtr = unsafe _storage.dict[id] {
            unsafe Unmanaged<AnyObject>.fromOpaque(oldPtr).release()
        }
        // Store new value (retained)
        let box = Ownership.Immutable(value)
        let ptr = unsafe UnsafeRawPointer(Unmanaged.passRetained(box).toOpaque())
        unsafe _storage.set(ptr, for: id)
    }

    // SAFETY: Operates entirely on the safe `Witness.Values` surface; the
    // SAFETY: underlying `_Storage`'s unsafe internals are encapsulated and
    // SAFETY: never exposed by this method.
    /// Creates a new values container by merging another into this one.
    ///
    /// Values from `other` override values in `self`.
    /// - Parameter other: The values to merge in.
    /// - Returns: A new values container with merged values.
    @safe
    public func merging(_ other: Witness.Values) -> Witness.Values {
        var result = Witness.Values()
        // Use prepared ref from other if present, otherwise from self
        result._preparedRef = other._preparedRef ?? self._preparedRef
        // Copy self's values using the internal copy method
        result._storage.copyFrom(_storage)
        // Override with other's values
        result._storage.copyFrom(other._storage)
        return result
    }
}

extension Witness.Values._Storage {
    @usableFromInline
    func set(_ ptr: UnsafeRawPointer, for key: ObjectIdentifier) {
        unsafe (dict[key] = ptr)
    }

    @usableFromInline
    func copyFrom(_ other: Witness.Values._Storage) {
        var iter = unsafe other.dict.makeIterator()
        while let (key, ptr) = unsafe iter.next() {
            if let oldPtr = unsafe dict[key] {
                unsafe Unmanaged<AnyObject>.fromOpaque(oldPtr).release()
            }
            _ = unsafe Unmanaged<AnyObject>.fromOpaque(ptr).retain()
            unsafe set(ptr, for: key)
        }
    }
}
