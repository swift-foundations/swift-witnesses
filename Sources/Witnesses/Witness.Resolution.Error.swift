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
    /// Errors that can occur during witness resolution.
    ///
    /// ## Design
    ///
    /// Per [API-NAME-001] (Nest.Name pattern), this is `Witness.Resolution.Error`
    /// rather than `WitnessResolutionError`.
    ///
    /// No existentials (`any Error`) - all error cases are fully typed.
    ///
    /// ## Cases
    ///
    /// - ``cycle(trace:)``: A cycle was detected in witness resolution.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// A cycle was detected in witness resolution.
        ///
        /// This occurs when a witness's computation depends (directly or
        /// indirectly) on itself.
        ///
        /// - Parameter trace: The resolution trace at the point of detection.
        case cycle(trace: Trace)
    }
}
