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

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Synchronization
import Witness_Primitives

extension Witness {
    /// Loud diagnostics for the resolution layer.
    ///
    /// The silent channel this closes: a ``Witness/Key/Test``-only key
    /// resolved in `.live` mode serves `testValue` with no report — a test
    /// default masquerading as domain behavior in production (incident class
    /// I2, `di-composition-root-design.md` §4.2). The diagnostic never
    /// resolves through the witness system itself.
    internal enum Diagnostics {
        /// Keys already reported in this process (release-mode report-once).
        private static let reported = Mutex<Set<ObjectIdentifier>>([])

        /// `DEPENDENCIES_STRICT=1` escalates the release-mode report to a
        /// trap, for smoke runs that want DEBUG-strength failure.
        private static let strict: Bool =
            getenv("DEPENDENCIES_STRICT").map { String(cString: $0) == "1" } ?? false

        /// Reports a test-only key's default being served in a live context.
        ///
        /// DEBUG builds trap — fail-fast in development, where this class is
        /// cheap. RELEASE builds report once per key to stderr and serve the
        /// default — availability-preserving: one forgotten key must not kill
        /// a serving process; the named report makes it a log-grep, not a
        /// debug round. `DEPENDENCIES_STRICT=1` traps in release.
        static func testDefaultServedInLive<K: Witness.Key.Test>(_ key: K.Type) {
            let message = """
                [swift-witnesses] Test default served in LIVE context: key '\(K.self)' \
                (value: \(K.Value.self)) has no liveValue (Witness.Key.Test-only) and was \
                resolved in .live mode with no explicit override or prepared value — its \
                testValue is standing in for production behavior. Register the value in the \
                app's composition root, or give the key a Witness.Key (liveValue) conformance \
                visible to the accessor's module. (di-composition-root-design.md §4.2)
                """
            #if DEBUG
            fatalError(message)
            #else
            if strict { fatalError(message) }
            let first = reported.withLock { $0.insert(ObjectIdentifier(K.self)).inserted }
            if first {
                message.withCString { _ = fputs($0, stderr) }
                _ = fputs("\n", stderr)
            }
            #endif
        }
    }
}
