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

/// Generates a `static func unimplemented()` method for `@Witness` structs.
///
/// This macro creates a total (non-crashing) placeholder implementation where
/// all operations throw `Witness.Unimplemented.Error` when invoked. This is the
/// recommended pattern for test doubles.
///
/// ## Usage
///
/// Apply alongside `@Witness`:
/// ```swift
/// @Witness
/// @WitnessUnimplemented
/// struct FileSystem: Sendable {
///     var open: @Sendable (_ path: String, _ flags: Int) async throws -> Int
///     var read: @Sendable (_ descriptor: Int, _ count: Int) async throws -> [UInt8]
///     var close: @Sendable (_ descriptor: Int) async throws -> Void
/// }
/// ```
///
/// ## Generated Code
///
/// The macro generates an extension with a static `unimplemented()` method:
/// ```swift
/// extension FileSystem {
///     public static func unimplemented(
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
///             // ... other closures
///         )
///     }
/// }
/// ```
///
/// ## Using in Tests
///
/// Start with unimplemented and override only what you need:
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
///
/// ## Total by Design
///
/// Unlike `fatalError`-based unimplemented patterns, this approach:
/// - Never crashes - always throws a typed error
/// - Provides clear diagnostics via `Witness.Unimplemented.Error`
/// - Includes source location where `unimplemented()` was called
/// - Complies with [API-IMPL-003] totality requirements
///
/// - Note: This macro requires the struct to also have the `@Witness` macro applied.
@attached(extension, names: named(unimplemented))
public macro WitnessUnimplemented() = #externalMacro(
    module: "Witnesses_Macros_Implementation",
    type: "WitnessUnimplementedMacro"
)
