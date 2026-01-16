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
    /// Namespace for unimplemented witness infrastructure.
    ///
    /// `Witness.Unimplemented` provides a total (non-crashing) pattern for creating
    /// placeholder witnesses that throw typed errors when invoked.
    ///
    /// ## Creating an Unimplemented Witness
    ///
    /// ```swift
    /// extension FileSystem {
    ///     static func unimplemented(
    ///         fileID: String = #fileID,
    ///         line: Int = #line
    ///     ) -> Self {
    ///         let location = Witness.Unimplemented.Location(fileID: fileID, line: line)
    ///         return Self(
    ///             open: { _, _ in
    ///                 throw Witness.Unimplemented.Error(
    ///                     witness: "FileSystem",
    ///                     operation: "open(path:flags:)",
    ///                     location: location
    ///                 )
    ///             },
    ///             read: { _, _ in
    ///                 throw Witness.Unimplemented.Error(
    ///                     witness: "FileSystem",
    ///                     operation: "read(descriptor:count:)",
    ///                     location: location
    ///                 )
    ///             },
    ///             close: { _ in
    ///                 throw Witness.Unimplemented.Error(
    ///                     witness: "FileSystem",
    ///                     operation: "close(descriptor:)",
    ///                     location: location
    ///                 )
    ///             }
    ///         )
    ///     }
    /// }
    /// ```
    ///
    /// ## Using in Tests
    ///
    /// In tests, start with an unimplemented witness and override only what you need:
    ///
    /// ```swift
    /// @Test
    /// func testFileReading() async throws {
    ///     var fs = FileSystem.unimplemented()
    ///     fs.read = { _, count in [UInt8](repeating: 0, count: count) }
    ///
    ///     // Only read is implemented; open/close will throw if called
    ///     let data = try await fs.read(descriptor: 1, count: 10)
    ///     #expect(data.count == 10)
    /// }
    /// ```
    public enum Unimplemented {}
}

// MARK: - Location

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

// MARK: - Error

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
