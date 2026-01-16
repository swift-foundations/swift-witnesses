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

@_exported public import Witness_Primitives
@_exported public import Optic_Primitives
@_exported public import Finite_Primitives

/// Generates protocol witness infrastructure for a struct with closure properties.
///
/// Apply `@Witness` to a struct containing closure properties to automatically generate:
/// - **Methods** with argument labels for closures that have labeled parameters
/// - **Action enum** with cases for each closure, useful for observation/middleware
/// - **`observe`** accessor to wrap the witness with observers
/// - **`unimplemented()`** static method that returns a witness where all operations throw
///
/// ## Basic Usage
///
/// ```swift
/// @Witness
/// struct APIClient: Sendable {
///     var fetchUser: (_ id: User.ID) async throws -> User
///     var updateUser: (_ id: User.ID, _ name: String) async throws -> User
///     var deleteUser: (_ id: User.ID) async throws -> Void
/// }
/// ```
///
/// This generates methods that can be called with labels:
///
/// ```swift
/// let client = APIClient.live
/// let user = try await client.fetchUser(id: 42)
/// try await client.updateUser(id: 42, name: "New Name")
/// ```
///
/// ## Labeled vs Unlabeled Closures
///
/// - **Labeled** (`(_ id: Int) -> T`): Generates a method with that label, deprecates the closure property
/// - **Unlabeled** (`(Int) -> T`): No method generated, closure remains the only API
///
/// ## Generated Action Enum
///
/// ```swift
/// extension APIClient {
///     enum Action: Sendable {
///         case fetchUser(id: User.ID)
///         case updateUser(id: User.ID, name: String)
///         case deleteUser(id: User.ID)
///     }
/// }
/// ```
///
/// ## Observation
///
/// ```swift
/// let observed = client.observe { action in
///     print("Called: \(action)")
/// }
/// ```
///
/// ## Unimplemented Witnesses
///
/// The macro automatically generates a static `unimplemented()` method for test doubles:
///
/// ```swift
/// @Test
/// func testUserDeletion() async throws {
///     var api = APIClient.unimplemented()
///     // Override only what you need
///     api.deleteUser = { _ in }
///
///     // Other operations will throw Witness.Unimplemented.Error if called
/// }
/// ```
///
/// The `unimplemented()` method creates a total (non-crashing) placeholder where all
/// operations throw `Witness.Unimplemented.Error` when invoked. This provides:
/// - Clear diagnostics with witness name, operation, and source location
/// - Type-safe error handling (throws, never crashes)
/// - Compliance with totality requirements
///
/// ## Platform Implementations
///
/// ```swift
/// // In swift-darwin-primitives
/// extension APIClient {
///     static var darwin: Self {
///         Self(
///             fetchUser: { id in /* Darwin implementation */ },
///             updateUser: { id, name in /* Darwin implementation */ },
///             deleteUser: { id in /* Darwin implementation */ }
///         )
///     }
/// }
/// ```
@attached(member, names: arbitrary)
@attached(memberAttribute)
@attached(extension, conformances: Witness_Primitives.__WitnessProtocol, Optic_Primitives.__OpticPrismAccessible, names: named(unimplemented))
public macro Witness() = #externalMacro(
    module: "Witnesses_Macros_Implementation",
    type: "WitnessMacro"
)
