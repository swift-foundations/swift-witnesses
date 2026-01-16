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

import Testing
public import Witnesses

/// Test witness for basic operations.
@Witness
struct TestAPI: Sendable {
    var fetch: @Sendable (_ id: Int) async throws(Witness.Unimplemented.Error) -> String
    var update: @Sendable (_ id: Int, _ value: String) async throws(Witness.Unimplemented.Error) -> Void
}

/// Test witness with mock derive option.
@Witness(.mock)
struct MockableAPI: Sendable {
    var fetchUser: @Sendable (_ id: Int) async throws(Witness.Unimplemented.Error) -> String
    var getCount: @Sendable () throws(Witness.Unimplemented.Error) -> Int
    var deleteUser: @Sendable (_ id: Int) async throws(Witness.Unimplemented.Error) -> Void
}

extension TestAPI: Witness.Key {
    static var liveValue: TestAPI {
        TestAPI(
            fetch: { id in "Live result for \(id)" },
            update: { _, _ in }
        )
    }

    static var testValue: TestAPI {
        TestAPI(
            fetch: { id in "Test result for \(id)" },
            update: { _, _ in }
        )
    }
}
