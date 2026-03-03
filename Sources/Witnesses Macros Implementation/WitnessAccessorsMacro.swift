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

// MARK: - WitnessAccessorsMacro

/// Macro that generates static service accessor methods for a witness type.
public struct WitnessAccessorsMacro {}

// MARK: - PeerMacro

extension WitnessAccessorsMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: node,
                message: WitnessAccessorsDiagnostic.requiresStruct
            ))
            return []
        }

        let closureProperties = extractClosurePropertiesForAccessors(from: structDecl)

        guard !closureProperties.isEmpty else {
            context.diagnose(Diagnostic(
                node: node,
                message: WitnessAccessorsDiagnostic.noClosureProperties
            ))
            return []
        }

        let structName = structDecl.name.text
        let isPublic = structDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
        let accessModifier = isPublic ? "public " : ""

        // Generate static accessor methods
        let accessorMethods = closureProperties.map { property in
            generateStaticAccessor(for: property, structName: structName, accessModifier: accessModifier)
        }.joined(separator: "\n\n    ")

        let extensionDecl: DeclSyntax = """
            extension \(raw: structName) {
                \(raw: accessorMethods)
            }
            """

        return [extensionDecl]
    }
}

// MARK: - Helpers

private struct AccessorClosureProperty {
    let name: String
    let parameters: [AccessorClosureParameter]
    let isAsync: Bool
    let isThrowing: Bool
    let throwsType: TypeSyntax?
    let returnType: TypeSyntax

    var methodName: String {
        if name.hasPrefix("_") {
            return String(name.dropFirst())
        }
        return name
    }
}

private struct AccessorClosureParameter {
    let label: String?
    let type: TypeSyntax
    let isInout: Bool
}

private func extractClosurePropertiesForAccessors(from structDecl: StructDeclSyntax) -> [AccessorClosureProperty] {
    var properties: [AccessorClosureProperty] = []

    for member in structDecl.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self),
              (varDecl.bindingSpecifier.tokenKind == .keyword(.var) ||
               varDecl.bindingSpecifier.tokenKind == .keyword(.let)),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation,
              let functionType = extractFunctionTypeForAccessors(from: typeAnnotation.type) else {
            continue
        }

        let parameters = extractParametersForAccessors(from: functionType)
        let throwsType: TypeSyntax? = functionType.effectSpecifiers?.throwsClause?.type

        properties.append(AccessorClosureProperty(
            name: identifier.identifier.text,
            parameters: parameters,
            isAsync: functionType.effectSpecifiers?.asyncSpecifier != nil,
            isThrowing: functionType.effectSpecifiers?.throwsClause != nil,
            throwsType: throwsType,
            returnType: functionType.returnClause.type
        ))
    }

    return properties
}

private func extractFunctionTypeForAccessors(from type: TypeSyntax) -> FunctionTypeSyntax? {
    if let functionType = type.as(FunctionTypeSyntax.self) {
        return functionType
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return extractFunctionTypeForAccessors(from: attributed.baseType)
    }
    return nil
}

private func extractParametersForAccessors(from functionType: FunctionTypeSyntax) -> [AccessorClosureParameter] {
    functionType.parameters.enumerated().map { index, param in
        let label: String? = {
            if let second = param.secondName?.text {
                return second
            }
            if let first = param.firstName?.text, first != "_" {
                return first
            }
            return nil
        }()
        let isInout = param.type.is(AttributedTypeSyntax.self) &&
            param.type.as(AttributedTypeSyntax.self)?.specifiers.contains(where: {
                $0.as(SimpleTypeSpecifierSyntax.self)?.specifier.tokenKind == .keyword(.inout)
            }) == true

        return AccessorClosureParameter(
            label: label,
            type: param.type,
            isInout: isInout
        )
    }
}

private func generateStaticAccessor(
    for property: AccessorClosureProperty,
    structName: String,
    accessModifier: String
) -> String {
    // Build parameter list
    let parameters = property.parameters.enumerated().map { index, param in
        let label = param.label ?? "_"
        let internalName = "p\(index)"
        return "\(label) \(internalName): \(param.type)"
    }.joined(separator: ", ")

    // Build effect specifiers
    var effectSpecs: [String] = []
    if property.isAsync { effectSpecs.append("async") }
    if property.isThrowing { effectSpecs.append("throws") }
    let effectSpecifiers = effectSpecs.isEmpty ? "" : " " + effectSpecs.joined(separator: " ")

    // Build return clause
    let returnType = property.returnType.trimmedDescription
    let returnClause = returnType == "Void" ? "" : " -> \(returnType)"

    // Build call arguments
    let callArguments = property.parameters.enumerated().map { index, param in
        let prefix = param.isInout ? "&" : ""
        let label = param.label.map { "\($0): " } ?? ""
        return "\(label)\(prefix)p\(index)"
    }.joined(separator: ", ")

    let awaitKeyword = property.isAsync ? "await " : ""
    let tryKeyword = property.isThrowing ? "try " : ""

    return """
    @inlinable
        \(accessModifier)static func \(property.methodName)(\(parameters))\(effectSpecifiers)\(returnClause) {
            \(tryKeyword)\(awaitKeyword)Witness.Context.current[Self.self].\(property.name)(\(callArguments))
        }
    """
}

// MARK: - Diagnostics

enum WitnessAccessorsDiagnostic: String, DiagnosticMessage {
    case requiresStruct
    case noClosureProperties

    var message: String {
        switch self {
        case .requiresStruct:
            return "@Witness.Accessors can only be applied to structs"
        case .noClosureProperties:
            return "@Witness.Accessors requires at least one closure property"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "WitnessAccessorsMacro", id: rawValue)
    }

    var severity: DiagnosticSeverity { .error }
}
