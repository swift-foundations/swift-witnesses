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

// MARK: - Witness.Derive

extension Witness {
    /// Options for deriving additional witness infrastructure.
    ///
    /// Pass these to `@Witness` to generate specialized test doubles:
    ///
    /// ```swift
    /// @Witness(.mock)
    /// struct APIClient: Sendable {
    ///     var fetchUser: (_ id: Int) async throws -> User
    /// }
    ///
    /// // Now you can create mocks with fixed return values:
    /// let api = APIClient.mock(fetchUser: User(id: 1, name: "Test"))
    /// ```
    ///
    /// Multiple modes can be combined:
    /// ```swift
    /// @Witness([.mock, .spy])
    /// struct APIClient { ... }
    /// ```
    public struct Derive: OptionSet, Sendable, Hashable {
        public let rawValue: UInt8

        @inlinable
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        /// Generate a `mock()` method that takes return values instead of closures.
        ///
        /// For Void-returning closures, the parameter has a default value of `()`.
        /// For non-Void closures, you must provide the return value.
        ///
        /// ```swift
        /// @Witness(.mock)
        /// struct API: Sendable {
        ///     var fetchUser: (_ id: Int) async throws -> User
        ///     var deleteUser: (_ id: Int) async throws -> Void
        /// }
        ///
        /// // Usage - provide values, not closures:
        /// let api = API.mock(fetchUser: testUser)  // deleteUser defaults to ()
        /// ```
        public static let mock = Derive(rawValue: 1 << 0)

        /// Generate `callAsFunction()` forwarding and `constant(_:)` static method.
        ///
        /// Use this for single-closure "generator" witnesses like Date or UUID:
        ///
        /// ```swift
        /// @Witness(.generator)
        /// struct DateGenerator: Sendable {
        ///     var now: @Sendable () -> Date
        /// }
        ///
        /// // Generates:
        /// // func callAsFunction() -> Date { now() }
        /// // static func constant(_ value: Date) -> Self { .init(now: { value }) }
        ///
        /// let generator = DateGenerator.constant(Date(timeIntervalSince1970: 0))
        /// print(generator())  // 1970-01-01
        /// ```
        public static let generator = Derive(rawValue: 1 << 1)
    }
}

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
@attached(extension, conformances: Witness_Primitives.__WitnessProtocol, Optic_Primitives.__OpticPrismAccessible, names: named(unimplemented), named(mock))
public macro Witness() = #externalMacro(
    module: "Witnesses_Macros_Implementation",
    type: "WitnessMacro"
)

/// Generates protocol witness infrastructure with additional derive modes.
///
/// ## Mock Mode
///
/// Use `@Witness(.mock)` to generate a `mock()` method that takes return values:
///
/// ```swift
/// @Witness(.mock)
/// struct APIClient: Sendable {
///     var fetchUser: (_ id: Int) async throws -> User
///     var deleteUser: (_ id: Int) async throws -> Void
/// }
///
/// // Create mock with fixed return values (no closures needed):
/// let api = APIClient.mock(fetchUser: User(id: 1, name: "Test"))
/// // deleteUser defaults to () since it returns Void
/// ```
///
/// Multiple modes can be combined:
/// ```swift
/// @Witness([.mock, .spy])
/// struct APIClient { ... }
/// ```
///
/// - Parameter derive: The derive modes to enable (e.g., `.mock`, `[.mock, .spy]`).
@attached(member, names: arbitrary)
@attached(memberAttribute)
@attached(extension, conformances: Witness_Primitives.__WitnessProtocol, Optic_Primitives.__OpticPrismAccessible, names: named(unimplemented), named(mock))
public macro Witness(_ derive: Witness.Derive) = #externalMacro(
    module: "Witnesses_Macros_Implementation",
    type: "WitnessMacro"
)

// MARK: - WitnessScope

/// Captures witness context at object creation time.
///
/// Apply `@WitnessScope` to a type to ensure that witness context is captured
/// when the object is created and automatically restored when methods are called.
/// This solves the problem where objects created inside a `Witness.Context.with` block
/// lose their context when methods are called from outside the block.
///
/// ## Problem
///
/// ```swift
/// let model: FeatureModel
/// Witness.Context.with { $0[APIClient.self] = .mock } operation: {
///     model = FeatureModel()  // Created with mock context
/// }
/// // Outside the block - context is lost!
/// try await model.process()  // Uses live APIClient, not mock
/// ```
///
/// ## Solution
///
/// ```swift
/// @WitnessScope
/// struct FeatureModel {
///     func process() async throws {
///         // Always uses context from when FeatureModel() was created
///         let api = Witness.Context.current[APIClient.self]
///     }
/// }
/// ```
///
/// ## Generated Code
///
/// The macro generates:
/// - A `_capturedContext` property that captures context at init time
/// - Method wrappers that restore the captured context before execution
///
/// ## Notes
///
/// - All methods in the type will have their context automatically restored
/// - The captured context is immutable after initialization
/// - Works with both sync and async methods
@attached(member, names: named(_capturedContext))
@attached(memberAttribute)
public macro WitnessScope() = #externalMacro(
    module: "Witnesses_Macros_Implementation",
    type: "WitnessScopeMacro"
)

// MARK: - WitnessAccessors

/// Generates static service accessor methods for a witness type.
///
/// Apply `@WitnessAccessors` alongside `@Witness` to generate static methods
/// that access the witness from the current context and forward calls to it.
/// This enables a more ergonomic API where you can call methods directly on
/// the type without first obtaining an instance.
///
/// ## Without Accessors
///
/// ```swift
/// let api = Witness.Context.current[APIClient.self]
/// let user = try await api.fetch(id: 1)
/// ```
///
/// ## With Accessors
///
/// ```swift
/// @Witness
/// @WitnessAccessors
/// struct APIClient: Sendable {
///     var fetch: (_ id: Int) async throws -> Data
/// }
///
/// // Now you can call directly:
/// let user = try await APIClient.fetch(id: 1)
/// ```
///
/// ## Generated Code
///
/// For each closure property, generates a static method that:
/// 1. Gets the witness from `Witness.Context.current`
/// 2. Forwards the call to the instance method
///
/// ```swift
/// extension APIClient {
///     public static func fetch(id: Int) async throws -> Data {
///         try await Witness.Context.current[Self.self].fetch(id: id)
///     }
/// }
/// ```
///
/// ## Requirements
///
/// - The type must conform to `Witness.Key`
/// - Must be used alongside `@Witness`
@attached(peer, names: arbitrary)
public macro WitnessAccessors() = #externalMacro(
    module: "Witnesses_Macros_Implementation",
    type: "WitnessAccessorsMacro"
)
