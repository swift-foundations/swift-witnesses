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
import Dependency_Primitives

extension Witness {
    /// Task-local context for witness dependency injection.
    ///
    /// `Witness.Context` provides scoped witness overrides via Task-local storage.
    /// Use ``with(_:operation:)-7r1dw`` to override witnesses for a scope:
    ///
    /// ```swift
    /// try await Witness.Context.with { values in
    ///     values[FileSystem.self] = .mock
    /// } operation: {
    ///     // FileSystem.self resolves to .mock here
    ///     let data = try await readFile()
    /// }
    /// ```
    ///
    /// ## Execution Mode
    ///
    /// Per [API-IMPL-002], mode is a state machine enum rather than a boolean.
    /// Use mode-aware context methods:
    ///
    /// ```swift
    /// Witness.Context.with(mode: .test) { values in
    ///     // values now resolve to testValue by default
    /// } operation: {
    ///     // ...
    /// }
    /// ```
    ///
    /// ## Accessing Current Values
    ///
    /// Within a scope, access the current witness values:
    ///
    /// ```swift
    /// let fs = Witness.Context.current[FileSystem.self]
    /// ```
    public struct Context: Sendable {
        /// Task-local storage for the current context.
        @TaskLocal
        private static var _current: Context = Context(values: Values(), mode: .live)

        /// The witness values in this context.
        public var values: Values

        /// The execution mode for this context.
        ///
        /// Determines which default value is used when a key is not
        /// explicitly overridden:
        /// - `.live`: Uses `liveValue`
        /// - `.preview`: Uses `previewValue`
        /// - `.test`: Uses `testValue`
        public var mode: Mode

        @usableFromInline
        internal init(values: Values, mode: Mode) {
            self.values = values
            self.mode = mode
        }
    }
}

// MARK: - Current Access

extension Witness.Context {
    /// The current witness values for this task.
    ///
    /// Returns the values from the innermost ``with(_:operation:)-7r1dw`` scope,
    /// or the default values if not in a scope.
    public static var current: Witness.Values {
        _current.values
    }

    /// The current execution mode for this task.
    ///
    /// Returns the mode from the innermost scope, or `.live` if not in a scope.
    public static var currentMode: Mode {
        _current.mode
    }
}

// MARK: - Value Access (Total API)

extension Witness.Context {
    /// Gets the current value for a key, with explicit mode.
    ///
    /// This is a convenience method that uses the current context's mode.
    ///
    /// - Parameter key: The key type to look up.
    /// - Returns: The resolved value for the key.
    public static subscript<K: Witness.Key>(key: K.Type) -> K.Value where K.Value: Copyable {
        _current.values.value(for: key, mode: _current.mode)
    }

    /// Gets the value for a key with full resolution (total API).
    ///
    /// Per [API-IMPL-003], this returns a `Result` rather than throwing or trapping.
    /// Currently returns `.success` always since basic lookup cannot fail.
    /// Future: will integrate cycle detection via `Resolution.Stack`.
    ///
    /// - Parameter key: The key type to resolve.
    /// - Returns: A result containing the resolved value or a resolution error.
    public static func value<K: Witness.Key>(_ key: K.Type) -> Result<K.Value, Witness.Resolution.Error> where K.Value: Copyable {
        .success(_current.values.value(for: key, mode: _current.mode))
    }

    /// Accesses the current value for a key via closure-scoped borrow.
    ///
    /// Works for all value types including `~Copyable`.
    ///
    /// - Parameters:
    ///   - key: The key type to look up.
    ///   - body: A closure that receives a borrow of the resolved value.
    /// - Returns: The result of `body`.
    public static func withValue<K: Witness.Key, R>(
        _ key: K.Type,
        _ body: (borrowing K.Value) -> R
    ) -> R {
        _current.values.withValue(for: key, mode: _current.mode, body)
    }
}

// MARK: - Scoped Override (Synchronous)

extension Witness.Context {
    /// Executes a closure with modified witness values.
    ///
    /// Per [API-ERR-003], typed errors are preserved by construction via Result.
    ///
    /// - Parameters:
    ///   - modify: A closure that modifies the witness values for the scope.
    ///   - operation: The operation to execute with the modified values.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    public static func with<T, E: Error>(
        _ modify: (inout Witness.Values) -> Void,
        operation: () throws(E) -> T
    ) throws(E) -> T {
        var context = _current
        modify(&context.values)
        return try $_current.withValue(context) {
            do throws(E) {
                return Result<T, E>.success(try operation())
            } catch {
                return Result<T, E>.failure(error)
            }
        }.get()
    }

    /// Executes a closure with modified witness values and mode.
    ///
    /// - Parameters:
    ///   - mode: The execution mode for the scope.
    ///   - modify: A closure that modifies the witness values for the scope.
    ///   - operation: The operation to execute with the modified values.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    public static func with<T, E: Error>(
        mode: Mode,
        _ modify: ((inout Witness.Values) -> Void)? = nil,
        operation: () throws(E) -> T
    ) throws(E) -> T {
        var context = _current
        context.mode = mode
        modify?(&context.values)
        return try Dependency.Scope.with({ $0.isTestContext = (mode == .test) }) {
            $_current.withValue(context) {
                do throws(E) {
                    return Result<T, E>.success(try operation())
                } catch {
                    return Result<T, E>.failure(error)
                }
            }
        }.get()
    }
}

// MARK: - Scoped Override (Asynchronous)

extension Witness.Context {
    /// Executes an async closure with modified witness values.
    ///
    /// This overload preserves actor isolation, allowing the operation to run
    /// in the caller's isolation context.
    ///
    /// Per [API-ERR-003], typed errors are preserved by construction via Result.
    ///
    /// - Parameters:
    ///   - isolation: The actor isolation context for the operation.
    ///   - modify: A closure that modifies the witness values for the scope.
    ///   - operation: The async operation to execute with the modified values.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    public static func with<T, E: Error>(
        isolation: isolated (any Actor)? = #isolation,
        _ modify: (inout Witness.Values) -> Void,
        operation: () async throws(E) -> T
    ) async throws(E) -> T {
        var context = _current
        modify(&context.values)
        return try await $_current.withValue(context) {
            do throws(E) {
                return Result<T, E>.success(try await operation())
            } catch {
                return Result<T, E>.failure(error)
            }
        }.get()
    }

    /// Executes an async closure with modified witness values and mode.
    ///
    /// - Parameters:
    ///   - isolation: The actor isolation context for the operation.
    ///   - mode: The execution mode for the scope.
    ///   - modify: A closure that modifies the witness values for the scope.
    ///   - operation: The async operation to execute with the modified values.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    public static func with<T, E: Error>(
        isolation: isolated (any Actor)? = #isolation,
        mode: Mode,
        _ modify: ((inout Witness.Values) -> Void)? = nil,
        operation: () async throws(E) -> T
    ) async throws(E) -> T {
        var context = _current
        context.mode = mode
        modify?(&context.values)
        let result: Result<T, E> = await Dependency.Scope.with({ $0.isTestContext = (mode == .test) }) {
            await $_current.withValue(context) {
                do throws(E) {
                    return Result<T, E>.success(try await operation())
                } catch {
                    return Result<T, E>.failure(error)
                }
            }
        }
        return try result.get()
    }
}

// MARK: - Mode-Specific Contexts (Synchronous)

extension Witness.Context {
    /// Executes a synchronous closure in test mode.
    ///
    /// In test mode, unset keys return their `testValue`.
    ///
    /// - Parameters:
    ///   - modify: An optional closure to further modify values.
    ///   - operation: The test operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    public static func withTest<T, E: Error>(
        _ modify: ((inout Witness.Values) -> Void)? = nil,
        operation: () throws(E) -> T
    ) throws(E) -> T {
        var context = _current
        context.mode = .test
        modify?(&context.values)
        return try Dependency.Scope.with({ $0.isTestContext = true }) {
            $_current.withValue(context) {
                do throws(E) {
                    return Result<T, E>.success(try operation())
                } catch {
                    return Result<T, E>.failure(error)
                }
            }
        }.get()
    }

    /// Executes a synchronous closure in preview mode.
    ///
    /// In preview mode, unset keys return their `previewValue`.
    ///
    /// - Parameters:
    ///   - modify: An optional closure to further modify values.
    ///   - operation: The preview operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    public static func withPreview<T, E: Error>(
        _ modify: ((inout Witness.Values) -> Void)? = nil,
        operation: () throws(E) -> T
    ) throws(E) -> T {
        var context = _current
        context.mode = .preview
        modify?(&context.values)
        return try Dependency.Scope.with({ $0.isTestContext = false }) {
            $_current.withValue(context) {
                do throws(E) {
                    return Result<T, E>.success(try operation())
                } catch {
                    return Result<T, E>.failure(error)
                }
            }
        }.get()
    }
}

// MARK: - Mode-Specific Contexts (Asynchronous)

extension Witness.Context {
    /// Executes an async closure in test mode.
    ///
    /// In test mode, unset keys return their `testValue`.
    ///
    /// - Parameters:
    ///   - modify: An optional closure to further modify values.
    ///   - operation: The test operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    public static func withTest<T, E: Error>(
        _ modify: ((inout Witness.Values) -> Void)? = nil,
        operation: () async throws(E) -> T
    ) async throws(E) -> T {
        var context = _current
        context.mode = .test
        modify?(&context.values)
        let result: Result<T, E> = await Dependency.Scope.with({ $0.isTestContext = true }) {
            await $_current.withValue(context) {
                do throws(E) {
                    return Result<T, E>.success(try await operation())
                } catch {
                    return Result<T, E>.failure(error)
                }
            }
        }
        return try result.get()
    }

    /// Executes an async closure in preview mode.
    ///
    /// In preview mode, unset keys return their `previewValue`.
    ///
    /// - Parameters:
    ///   - modify: An optional closure to further modify values.
    ///   - operation: The preview operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: The typed error from the operation.
    public static func withPreview<T, E: Error>(
        _ modify: ((inout Witness.Values) -> Void)? = nil,
        operation: () async throws(E) -> T
    ) async throws(E) -> T {
        var context = _current
        context.mode = .preview
        modify?(&context.values)
        let result: Result<T, E> = await Dependency.Scope.with({ $0.isTestContext = false }) {
            await $_current.withValue(context) {
                do throws(E) {
                    return Result<T, E>.success(try await operation())
                } catch {
                    return Result<T, E>.failure(error)
                }
            }
        }
        return try result.get()
    }
}
