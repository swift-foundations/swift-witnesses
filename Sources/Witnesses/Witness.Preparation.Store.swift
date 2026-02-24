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

import Synchronization
public import Ownership_Primitives

extension Witness.Preparation {
    /// Thread-safe store for prepared witness values.
    ///
    /// `Store` provides type-safe storage for witnesses that are prepared
    /// ahead of time, typically during app startup.
    ///
    /// ## Design
    ///
    /// - Pointer-backed internally to avoid existential overhead
    /// - Uses ``Ownership/Shared`` for value storage (consistent with Values)
    /// - Thread-safe via `Mutex`
    /// - Carried via `@TaskLocal` per [API-IMPL-010]
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let store = Witness.Preparation.Store()
    /// store.set(FileSystem.self, value: .darwin)
    /// let fs = store.get(FileSystem.self)  // FileSystem?
    /// ```
    @safe
    public final class Store: @unchecked Sendable {
        /// Internal storage mapping type identifiers to boxed values.
        private var storage: [ObjectIdentifier: UnsafeRawPointer]

        /// Lock for thread-safe access.
        private let lock: Mutex<Void>

        /// Creates an empty store.
        public init() {
            self.storage = [:]
            self.lock = Mutex(())
        }

        /// Gets the prepared value for a key type.
        ///
        /// - Parameter key: The key type to look up.
        /// - Returns: The prepared value, or `nil` if not prepared.
        public func get<K: Witness.Key>(_ key: K.Type) -> K.Value? {
            lock.withLock { _ in
                let id = ObjectIdentifier(K.self)
                guard let ptr = unsafe storage[id] else {
                    return nil
                }
                return unsafe Unmanaged<Ownership.Shared<K.Value>>.fromOpaque(ptr)
                    .takeUnretainedValue()
                    .value
            }
        }

        /// Sets the prepared value for a key type.
        ///
        /// - Parameters:
        ///   - key: The key type.
        ///   - value: The value to store.
        public func set<K: Witness.Key>(_ key: K.Type, value: K.Value) {
            lock.withLock { _ in
                let id = ObjectIdentifier(K.self)

                // Release old value if present
                if let oldPtr = unsafe storage[id] {
                    unsafe Unmanaged<AnyObject>.fromOpaque(oldPtr).release()
                }

                // Store new value (retained)
                let box = Ownership.Shared(value)
                let ptr = unsafe UnsafeRawPointer(Unmanaged.passRetained(box).toOpaque())
                unsafe storage[id] = ptr
            }
        }

        /// Removes the prepared value for a key type.
        ///
        /// - Parameter key: The key type.
        /// - Returns: The removed value, or `nil` if not present.
        @discardableResult
        public func remove<K: Witness.Key>(_ key: K.Type) -> K.Value? {
            lock.withLock { _ in
                let id = ObjectIdentifier(K.self)
                guard let ptr = unsafe storage.removeValue(forKey: id) else {
                    return nil
                }
                let box = unsafe Unmanaged<Ownership.Shared<K.Value>>.fromOpaque(ptr)
                    .takeRetainedValue()
                return box.value
            }
        }

        /// Releases all retained boxes on deallocation.
        deinit {
            for ptr in storage.values {
                unsafe Unmanaged<AnyObject>.fromOpaque(ptr).release()
            }
        }
    }
}
