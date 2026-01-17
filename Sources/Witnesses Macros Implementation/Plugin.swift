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

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct WitnessesMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        WitnessMacro.self,
        WitnessScopeMacro.self,
        WitnessAccessorsMacro.self,
    ]
}
