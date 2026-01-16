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

extension Witness.Unimplemented {
    /// Source location where an unimplemented witness was created.
    public struct Location: Sendable, Hashable {
        /// The file ID where the unimplemented witness was created.
        public let fileID: String

        /// The line number where the unimplemented witness was created.
        public let line: Int

        /// Creates a source location.
        @inlinable
        public init(fileID: String = #fileID, line: Int = #line) {
            self.fileID = fileID
            self.line = line
        }
    }
}
