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
public import Synchronization

extension Witness {
    /// Returns values from a sequence in order, staying on the last value when exhausted.
    ///
    /// Use `Witness.Sequence` to create mock witnesses that return different values
    /// on successive calls:
    ///
    /// ```swift
    /// let responses = Witness.Sequence(["first", "second", "third"])
    ///
    /// let mock = APIClient(
    ///     fetch: { _ in responses() }
    /// )
    ///
    /// print(mock.fetch(id: 1))  // "first"
    /// print(mock.fetch(id: 2))  // "second"
    /// print(mock.fetch(id: 3))  // "third"
    /// print(mock.fetch(id: 4))  // "third" (stays on last)
    /// ```
    ///
    /// This is useful for testing scenarios where you need predictable,
    /// sequential return values without writing mutable state management.
    public final class Sequence<T: Sendable>: @unchecked Sendable {
        @usableFromInline
        internal let values: [T]

        @usableFromInline
        internal let _index: Mutex<Int>

        /// Creates a sequence that returns values in order.
        ///
        /// - Parameter values: The values to return. Must not be empty.
        /// - Precondition: `values` must not be empty.
        @inlinable
        public init(_ values: [T]) {
            precondition(!values.isEmpty, "Witness.Sequence requires at least one value")
            self.values = values
            self._index = Mutex(0)
        }

        /// Returns the next value in the sequence.
        ///
        /// When all values have been returned, continues returning the last value.
        @inlinable
        public func callAsFunction() -> T {
            let i = _index.withLock { index -> Int in
                let current = index
                index += 1
                return current
            }
            return values[min(i, values.count - 1)]
        }
    }
}
