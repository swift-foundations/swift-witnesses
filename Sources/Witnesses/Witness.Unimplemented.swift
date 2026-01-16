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
