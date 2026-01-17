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
    /// For witnesses with multiple parameters, use a tuple:
    ///
    /// ```swift
    /// let recording = Witness.Recording<(id: Int, name: String)>()
    ///
    /// let mock = UserClient(
    ///     update: { id, name in recording.record((id: id, name: name)) }
    /// )
    ///
    /// mock.update(id: 1, name: "Alice")
    /// #expect(recording.calls.first?.id == 1)
    /// ```
    public final class Recording<Args: Sendable>: @unchecked Sendable {
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
