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
    /// Error thrown when an unimplemented witness operation is invoked.
    ///
    /// This error provides detailed information about what was called and where
    /// the unimplemented witness was created, enabling clear test diagnostics.
    public struct Error: Swift.Error, Sendable, Hashable {
        /// The name of the witness type.
        public let witness: String

        /// The name of the operation that was called.
        public let operation: String

        /// The source location where the unimplemented witness was created.
        public let location: Location

        /// Creates an unimplemented error.
        ///
        /// - Parameters:
        ///   - witness: The name of the witness type (e.g., "FileSystem").
        ///   - operation: The name of the operation called (e.g., "open(path:flags:)").
        ///   - location: The source location where `unimplemented()` was called.
        @inlinable
        public init(witness: String, operation: String, location: Location) {
            self.witness = witness
            self.operation = operation
            self.location = location
        }
    }
}

extension Witness.Unimplemented.Error: CustomStringConvertible {
    public var description: String {
        "\(witness).\(operation) is not implemented (created at \(location.fileID):\(location.line))"
    }
}
