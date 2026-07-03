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

internal import Ownership_Primitives
import Synchronization

extension Witness.Preparation {
    /// Thread-safe store for prepared witness values.
    ///
    /// `Store` provides type-safe storage for witnesses that are prepared
    /// ahead of time, typically during app startup.
    ///
    /// ## Safety Invariant
    ///
    /// All mutable state (`storage` dictionary) is guarded by a `Mutex`. Every
    /// mutation path (`set`, `remove`) and every read (`get`, `withValue`) goes
    /// through `lock.withLock`. `deinit` releases all retained boxes. The
    /// pointer-backed storage avoids existential overhead (8 bytes vs 40 bytes
    /// per entry) but the Mutex serialization is the Sendable invariant.
    ///
    /// ## Intended Use
    ///
    /// - Type-safe storage for witnesses prepared ahead of time (app startup).
    /// - Carried via `@TaskLocal` per [API-IMPL-010].
    /// - Thread-safe shared configuration across concurrent test invocations.
    ///
    /// ## Non-Goals
    ///
    /// - Not a general-purpose dictionary. Keyed by `Witness.Key` type identity only.
    /// - Does NOT provide change notification or observation.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let store = Witness.Preparation.Store()
    /// store.set(FileSystem.self, value: .darwin)
    /// let fs = store.get(FileSystem.self)  // FileSystem?
    /// ```
    @safe
    public final class Store: @unsafe @unchecked Sendable {
        /// Internal storage mapping type identifiers to boxed values.
        private var storage: [ObjectIdentifier: UnsafeRawPointer]

        /// Lock for thread-safe access.
        private let lock: Mutex<Void>

        /// Creates an empty store.
        public init() {
            unsafe (self.storage = [:])
            self.lock = Mutex(())
        }

        /// Gets the prepared value for a key type.
        ///
        /// - Parameter key: The key type to look up.
        /// - Returns: The prepared value, or `nil` if not prepared.
        public func get<K: Witness.Key>(_ key: K.Type) -> K.Value? where K.Value: Copyable {
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

        /// Accesses the prepared value for a key type via closure-scoped borrow.
        ///
        /// Works for all value types including `~Copyable`.
        ///
        /// - Parameters:
        ///   - key: The key type to look up.
        ///   - body: A closure that receives a borrow of the prepared value.
        /// - Returns: The result of `body`, or `nil` if no value is prepared.
        public func withValue<K: Witness.Key, R>(
            _ key: K.Type,
            _ body: (borrowing K.Value) -> R
        ) -> R? {
            lock.withLock { _ in
                let id = ObjectIdentifier(K.self)
                guard let ptr = unsafe storage[id] else { return nil }
                return body(
                    unsafe Unmanaged<Ownership.Shared<K.Value>>.fromOpaque(ptr)
                        .takeUnretainedValue()
                        .value
                )
            }
        }

        /// Sets the prepared value for a key type.
        ///
        /// - Parameters:
        ///   - key: The key type.
        ///   - value: The value to store.
        public func set<K: Witness.Key>(_ key: K.Type, value: consuming K.Value) {
            // Box and retain before entering the lock — consuming moves happen here.
            let ptr = unsafe UnsafeRawPointer(
                Unmanaged.passRetained(Ownership.Shared(value)).toOpaque()
            )
            lock.withLock { _ in
                let id = ObjectIdentifier(K.self)

                // Release old value if present
                if let oldPtr = unsafe storage[id] {
                    unsafe Unmanaged<AnyObject>.fromOpaque(oldPtr).release()
                }

                unsafe storage[id] = ptr
            }
        }

        /// Removes the prepared value for a key type.
        ///
        /// - Parameter key: The key type.
        /// - Returns: The removed value, or `nil` if not present.
        @discardableResult
        public func remove<K: Witness.Key>(_ key: K.Type) -> K.Value? where K.Value: Copyable {
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
            var iter = unsafe storage.values.makeIterator()
            while let ptr = unsafe iter.next() {
                unsafe Unmanaged<AnyObject>.fromOpaque(ptr).release()
            }
        }
    }
}
