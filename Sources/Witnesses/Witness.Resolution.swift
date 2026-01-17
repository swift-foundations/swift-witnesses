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

extension Witness {
    /// Namespace for witness resolution infrastructure.
    ///
    /// Contains types for tracking resolution state and detecting cycles:
    /// - ``Trace``: Structural trace of resolution path
    /// - ``Error``: Typed resolution errors
    /// - ``Stack``: TaskLocal resolution stack with cycle detection
    public enum Resolution {}
}
