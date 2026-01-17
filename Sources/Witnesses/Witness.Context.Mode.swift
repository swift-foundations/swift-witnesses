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

extension Witness.Context {
    /// The execution mode for witness resolution.
    ///
    /// Replaces the boolean `isTestContext` per [API-IMPL-002] - state machine enum over boolean.
    ///
    /// ## Modes
    ///
    /// - `live`: Production mode. Keys resolve to `liveValue`.
    /// - `preview`: Preview mode. Keys resolve to `previewValue`.
    /// - `test`: Test mode. Keys resolve to `testValue`.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// Witness.Context.with(mode: .test) {
    ///     // Keys now resolve to testValue
    /// }
    /// ```
    public enum Mode: Sendable, Equatable {
        /// Production context. Keys resolve to `liveValue`.
        case live

        /// Preview context. Keys resolve to `previewValue`.
        case preview

        /// Test context. Keys resolve to `testValue`.
        case test
    }
}
