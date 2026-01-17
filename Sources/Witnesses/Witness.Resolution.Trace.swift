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

extension Witness.Resolution {
    /// A structural trace of the resolution path.
    ///
    /// Used to provide diagnostic information when resolution errors occur,
    /// particularly for cycle detection.
    ///
    /// ## Design
    ///
    /// Per [API-IMPL-003] (primitives must be total), this type uses
    /// `ObjectIdentifier` rather than String for type identification.
    /// No existentials per primitive layer constraints.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// switch error {
    /// case .cycle(let trace):
    ///     print("Cycle in resolution: \(trace.stack.count) keys")
    ///     print("Mode: \(trace.mode)")
    /// }
    /// ```
    public struct Trace: Sendable, Equatable {
        /// The resolution stack at the point of the trace.
        ///
        /// For cycle errors, this includes the key that caused the cycle
        /// as the last element (appearing twice in the logical sequence).
        public let stack: [ObjectIdentifier]

        /// The execution mode at the point of the trace.
        public let mode: Witness.Context.Mode

        /// Creates a trace with the given stack and mode.
        ///
        /// - Parameters:
        ///   - stack: The resolution stack (key identifiers).
        ///   - mode: The execution mode.
        @inlinable
        public init(stack: [ObjectIdentifier], mode: Witness.Context.Mode) {
            self.stack = stack
            self.mode = mode
        }
    }
}
