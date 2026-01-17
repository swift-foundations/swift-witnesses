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
public import Reference_Primitives

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
        /// Internal storage with proper memory cleanup.
        /// Uses UnsafeRawPointer to avoid existential overhead (8 bytes vs 40 bytes per entry).
        @safe @usableFromInline
        final class _Storage: @unchecked Sendable {
            @usableFromInline
            var dict: [ObjectIdentifier: UnsafeRawPointer]

            @usableFromInline
            init() {
                self.dict = [:]
            }

            @usableFromInline
            func set(_ ptr: UnsafeRawPointer, for key: ObjectIdentifier) {
                dict[key] = ptr
            }

            /// Releases all retained boxes on deallocation.
            deinit {
                for key in dict.keys {
                    if let ptr = dict[key] {
                        unsafe Unmanaged<AnyObject>.fromOpaque(ptr).release()
                    }
                }
            }
        }

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
    /// Ensures unique storage for mutation (Copy-on-Write).
    @inlinable
    mutating func _ensureUnique() {
        if !isKnownUniquelyReferenced(&_storage) {
            let newStorage = _Storage()
            // Copy all entries (retaining each box)
            for key in unsafe _storage.dict.keys {
                if let ptr = unsafe _storage.dict[key] {
                    _ = unsafe Unmanaged<AnyObject>.fromOpaque(ptr).retain()
                    unsafe newStorage.set(ptr, for: key)
                }
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
    internal func value<K: Witness.Key>(for key: K.Type, mode: Witness.Context.Mode) -> K.Value {
        let id = ObjectIdentifier(K.self)

        // 1. Check explicit overrides
        if let ptr = unsafe _storage.dict[id] {
            return unsafe Unmanaged<Reference.Box<K.Value>>.fromOpaque(ptr)
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

    /// Accesses the witness for the given key type.
    ///
    /// For get operations, uses `.live` mode by default. For mode-aware access,
    /// use ``Witness/Context`` which provides the current mode.
    ///
    /// - Parameter key: The key type identifying the witness.
    /// - Returns: The stored witness, or the key's `liveValue` if not set.
    @inlinable
    public subscript<K: Witness.Key>(key: K.Type) -> K.Value {
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
            let box = Reference.Box(newValue)
            let ptr = unsafe UnsafeRawPointer(Unmanaged.passRetained(box).toOpaque())
            unsafe _storage.set(ptr, for: id)
        }
    }

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
    func copyFrom(_ other: Witness.Values._Storage) {
        for key in unsafe other.dict.keys {
            if let ptr = unsafe other.dict[key] {
                // Release old value if present
                if let oldPtr = unsafe dict[key] {
                    unsafe Unmanaged<AnyObject>.fromOpaque(oldPtr).release()
                }
                _ = unsafe Unmanaged<AnyObject>.fromOpaque(ptr).retain()
                unsafe set(ptr, for: key)
            }
        }
    }
}
