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

/// Executes a synchronous operation with modified witness values.
///
/// This is a convenience wrapper around `Witness.Context.with(_:operation:)`:
///
/// ```swift
/// let result = try withWitnesses { values in
///     values[FileSystem.self] = .mock
///     values[Logger.self] = .console
/// } operation: {
///     try processFiles()
/// }
/// ```
///
/// Per [API-ERR-001], typed errors are preserved through the operation.
///
/// - Parameters:
///   - modify: A closure that modifies the witness values for the scope.
///   - operation: The operation to execute with the modified values.
/// - Returns: The result of the operation.
/// - Throws: The typed error from the operation.
@inlinable
public func withWitnesses<T, E: Swift.Error>(
    _ modify: (inout Witness.Values) -> Void,
    operation: () throws(E) -> T
) throws(E) -> T {
    try Witness.Context.with(modify, operation: operation)
}

/// Executes an asynchronous operation with modified witness values.
///
/// This is a convenience wrapper around `Witness.Context.with(_:operation:)`:
///
/// ```swift
/// let result = try await withWitnesses { values in
///     values[APIClient.self] = .mock
///     values[Database.self] = .inMemory
/// } operation: {
///     try await fetchAndStoreData()
/// }
/// ```
///
/// Per [API-ERR-001], typed errors are preserved through the operation.
///
/// - Parameters:
///   - modify: A closure that modifies the witness values for the scope.
///   - operation: The async operation to execute with the modified values.
/// - Returns: The result of the operation.
/// - Throws: The typed error from the operation.
@inlinable
nonisolated(nonsending)
    public func withWitnesses<T, E: Swift.Error>(
        _ modify: (inout Witness.Values) -> Void,
        operation: nonisolated(nonsending) () async throws(E) -> T
    ) async throws(E) -> T
{
    try await Witness.Context.with(modify, operation: operation)
}
