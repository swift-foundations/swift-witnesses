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

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

// MARK: - WitnessScopeMacro

/// Macro that captures witness context at object creation time.
public struct WitnessScopeMacro {}

// MARK: - MemberMacro

extension WitnessScopeMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Generate the _capturedContext property
        return [
            """
            private let _capturedContext = Witness.CapturedContext()
            """
        ]
    }
}

// MARK: - MemberAttributeMacro

extension WitnessScopeMacro: MemberAttributeMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        // We don't add attributes to members - the context capture happens at runtime
        // through the _capturedContext property that users reference explicitly
        return []
    }
}
