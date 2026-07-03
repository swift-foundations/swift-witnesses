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

public import Synchronization
import Witness_Primitives

extension Witness {
    /// Cycles through values forever, wrapping around when exhausted.
    ///
    /// Use `Witness.Cycle` to create mock witnesses that cycle through a set of values:
    ///
    /// ```swift
    /// let statuses = Witness.Cycle(["pending", "processing", "complete"])
    ///
    /// let mock = JobClient(
    ///     getStatus: { _ in statuses() }
    /// )
    ///
    /// print(mock.getStatus(id: 1))  // "pending"
    /// print(mock.getStatus(id: 2))  // "processing"
    /// print(mock.getStatus(id: 3))  // "complete"
    /// print(mock.getStatus(id: 4))  // "pending" (cycles back)
    /// ```
    ///
    /// ## Safety Invariant
    ///
    /// This type is `Sendable` by virtue of internal synchronization: `_index`
    /// is protected by `Mutex<Int>`. Every `callAsFunction()` mutates the index
    /// exclusively through `_index.withLock`. The `values` array is immutable
    /// after init (read-only). `T: Sendable` closes the element-Sendable gap.
    ///
    /// ## Intended Use
    ///
    /// - Mock witnesses that cycle through a repeating pattern of values in tests.
    /// - Thread-safe shared fixture across concurrent test invocations.
    ///
    /// ## Non-Goals
    ///
    /// - Not a finite sequence. For exhaust-then-stay-on-last use `Witness.Sequence`.
    /// - Not resettable. The cycle position is monotonically advancing.
    public final class Cycle<T: Sendable>: @unsafe @unchecked Sendable {
        @usableFromInline
        internal let values: [T]

        @usableFromInline
        internal let _index: Mutex<Int>

        /// Creates a cycle that returns values in order, wrapping around.
        ///
        /// - Parameter values: The values to cycle through. Must not be empty.
        /// - Precondition: `values` must not be empty.
        @inlinable
        public init(_ values: [T]) {
            precondition(!values.isEmpty, "Witness.Cycle requires at least one value")
            self.values = values
            self._index = Mutex(0)
        }

        /// Returns the next value in the cycle.
        ///
        /// Wraps around to the first value after returning the last.
        @inlinable
        public func callAsFunction() -> T {
            let i = _index.withLock { index -> Int in
                let current = index
                index = (current + 1) % values.count
                return current
            }
            return values[i]
        }
    }
}
