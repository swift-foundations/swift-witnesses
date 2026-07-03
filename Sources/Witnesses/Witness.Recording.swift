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
    /// Records all calls for later inspection.
    ///
    /// Use `Witness.Recording` to capture and verify calls made to a witness:
    ///
    /// ```swift
    /// let recording = Witness.Recording<String>()
    ///
    /// let mock = Logger(
    ///     log: { message in recording.record(message) }
    /// )
    ///
    /// mock.log("Hello")
    /// mock.log("World")
    ///
    /// #expect(recording.calls == ["Hello", "World"])
    /// ```
    ///
    /// ## Safety Invariant
    ///
    /// All mutable state (`_calls`) is guarded by `Mutex<[Args]>`. Every
    /// `record` / `reset` / accessor routes through `_calls.withLock`.
    /// `Args: Sendable` closes the generic element gap.
    ///
    /// ## Intended Use
    ///
    /// - Capture and verify calls made to a witness in tests.
    /// - Thread-safe recording across concurrent test invocations.
    ///
    /// ## Non-Goals
    ///
    /// - Not a general-purpose event log. For structured test events use the
    ///   test reporter infrastructure.
    /// - Does NOT provide change notification or observation.
    public final class Recording<Args: Sendable>: @unsafe @unchecked Sendable {
        @usableFromInline
        internal let _calls: Mutex<[Args]>

        /// The recorded calls.
        @inlinable
        public var calls: [Args] {
            _calls.withLock { $0 }
        }

        /// Creates an empty recording.
        @inlinable
        public init() {
            self._calls = Mutex([])
        }

        /// Records a call with the given arguments.
        ///
        /// - Parameter args: The arguments to record.
        @inlinable
        public func record(_ args: Args) {
            _calls.withLock { $0.append(args) }
        }

        /// Clears all recorded calls.
        @inlinable
        public func reset() {
            _calls.withLock { $0.removeAll() }
        }

        /// The number of recorded calls.
        @inlinable
        public var count: Int {
            _calls.withLock { $0.count }
        }

        /// Whether any calls have been recorded.
        @inlinable
        public var isEmpty: Bool {
            _calls.withLock { $0.isEmpty }
        }

        /// Returns the last recorded call, if any.
        @inlinable
        public var last: Args? {
            _calls.withLock { $0.last }
        }

        /// Returns the first recorded call, if any.
        @inlinable
        public var first: Args? {
            _calls.withLock { $0.first }
        }
    }
}
