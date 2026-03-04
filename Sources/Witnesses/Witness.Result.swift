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

extension Witness {
    public enum Result<Success: ~Copyable & Sendable, Failure: Error & Sendable>: ~Copyable, Sendable {
        case success(Success)
        case failure(Failure)
    }
}

extension Witness.Result: Copyable where Success: Copyable {}
