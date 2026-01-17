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
    /// Values not explicitly set will return their key's `liveValue` or `testValue`
    /// depending on the current context.
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

        /// Storage using type identifier as key with UnsafeRawPointer values.
        @usableFromInline
        internal var _storage: _Storage

        /// Whether we're in a test context.
        @usableFromInline
        internal var isTestContext: Bool

        /// Creates an empty values container.
        ///
        /// - Parameter isTestContext: If `true`, unset keys return `testValue` instead of `liveValue`.
        @inlinable
        public init(isTestContext: Bool = false) {
            self._storage = _Storage()
            self.isTestContext = isTestContext
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
            for key in _storage.dict.keys {
                if let ptr = unsafe _storage.dict[key] {
                    _ = unsafe Unmanaged<AnyObject>.fromOpaque(ptr).retain()
                    unsafe newStorage.set(ptr, for: key)
                }
            }
            _storage = newStorage
        }
    }

    /// Accesses the witness for the given key type.
    ///
    /// - Parameter key: The key type identifying the witness.
    /// - Returns: The stored witness, or the key's default value if not set.
    @inlinable
    public subscript<K: Witness.Key>(key: K.Type) -> K.Value {
        get {
            let id = ObjectIdentifier(K.self)
            if let ptr = unsafe _storage.dict[id] {
                return unsafe Unmanaged<Reference.Box<K.Value>>.fromOpaque(ptr).takeUnretainedValue().value
            }
            return isTestContext ? K.testValue : K.liveValue
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
    @inlinable
    public func merging(_ other: Witness.Values) -> Witness.Values {
        var result = Witness.Values(isTestContext: self.isTestContext || other.isTestContext)
        // Copy self's values
        for key in _storage.dict.keys {
            if let ptr = unsafe _storage.dict[key] {
                _ = unsafe Unmanaged<AnyObject>.fromOpaque(ptr).retain()
                unsafe result._storage.set(ptr, for: key)
            }
        }
        // Override with other's values
        for key in other._storage.dict.keys {
            if let ptr = unsafe other._storage.dict[key] {
                // Release old value if present in result
                if let oldPtr = unsafe result._storage.dict[key] {
                    unsafe Unmanaged<AnyObject>.fromOpaque(oldPtr).release()
                }
                _ = unsafe Unmanaged<AnyObject>.fromOpaque(ptr).retain()
                unsafe result._storage.set(ptr, for: key)
            }
        }
        return result
    }
}
