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

@_spi(RawSyntax) import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

// MARK: - WitnessUnimplementedMacro

/// Generates a `static func unimplemented()` method for `@Witness` structs.
///
/// This macro is part of the Foundations layer and generates total (non-crashing)
/// placeholder implementations that throw `Witness.Unimplemented.Error`.
///
/// Usage:
/// ```swift
/// @Witness
/// @WitnessUnimplemented
/// struct FileSystem: Sendable {
///     var open: @Sendable (_ path: String) async throws -> Int
///     var close: @Sendable (_ fd: Int) async throws -> Void
/// }
/// ```
///
/// Generates:
/// ```swift
/// extension FileSystem {
///     public static func unimplemented(
///         fileID: String = #fileID,
///         line: Int = #line
///     ) -> Self {
///         let location = Witness.Unimplemented.Location(fileID: fileID, line: line)
///         return Self(
///             open: { _ in
///                 throw Witness.Unimplemented.Error(
///                     witness: "FileSystem",
///                     operation: "open(path:)",
///                     location: location
///                 )
///             },
///             close: { _ in
///                 throw Witness.Unimplemented.Error(
///                     witness: "FileSystem",
///                     operation: "close(fd:)",
///                     location: location
///                 )
///             }
///         )
///     }
/// }
/// ```
public struct WitnessUnimplementedMacro {}

// MARK: - ExtensionMacro

extension WitnessUnimplementedMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Only handle struct declarations
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: node,
                message: UnimplementedDiagnostic.requiresStruct
            ))
            return []
        }

        let closureProperties = extractClosureProperties(from: structDecl)

        guard !closureProperties.isEmpty else {
            context.diagnose(Diagnostic(
                node: node,
                message: UnimplementedDiagnostic.noClosureProperties
            ))
            return []
        }

        let structName = structDecl.name.text
        let isPublic = structDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
        let accessModifier = isPublic ? "public " : ""

        // Generate closure initializers that throw Witness.Unimplemented.Error
        let closureInits = closureProperties.map { property in
            generateUnimplementedClosure(for: property, structName: structName)
        }.joined(separator: ",\n            ")

        let extensionDecl = try ExtensionDeclSyntax(
            """
            extension \(type.trimmed) {
                /// Creates an unimplemented witness where all operations throw `Witness.Unimplemented.Error`.
                ///
                /// Use this in tests to start with a placeholder and override only what you need:
                /// ```swift
                /// var api = \(raw: structName).unimplemented()
                /// api.fetch = { id in "mocked result" }
                /// ```
                @inlinable
                \(raw: accessModifier)static func unimplemented(
                    fileID: String = #fileID,
                    line: Int = #line
                ) -> Self {
                    let location = Witness.Unimplemented.Location(fileID: fileID, line: line)
                    return Self(
                        \(raw: closureInits)
                    )
                }
            }
            """
        )

        return [extensionDecl]
    }
}

// MARK: - Property Extraction

struct ClosureProperty {
    let name: String
    let functionType: FunctionTypeSyntax
    let parameters: [ClosureParameter]
    let isAsync: Bool
    let isThrowing: Bool
    let returnType: TypeSyntax
}

struct ClosureParameter {
    let label: String?
    let type: TypeSyntax
}

private func extractClosureProperties(from structDecl: StructDeclSyntax) -> [ClosureProperty] {
    var properties: [ClosureProperty] = []

    for member in structDecl.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self),
              varDecl.bindingSpecifier.tokenKind == .keyword(.var),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation,
              let functionType = extractFunctionType(from: typeAnnotation.type) else {
            continue
        }

        let parameters = extractParameters(from: functionType)

        properties.append(ClosureProperty(
            name: identifier.identifier.text,
            functionType: functionType,
            parameters: parameters,
            isAsync: functionType.effectSpecifiers?.asyncSpecifier != nil,
            isThrowing: functionType.effectSpecifiers?.throwsClause != nil,
            returnType: functionType.returnClause.type
        ))
    }

    return properties
}

private func extractFunctionType(from type: TypeSyntax) -> FunctionTypeSyntax? {
    // Direct function type
    if let functionType = type.as(FunctionTypeSyntax.self) {
        return functionType
    }

    // Attributed type (e.g., @Sendable)
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return extractFunctionType(from: attributed.baseType)
    }

    return nil
}

private func extractParameters(from functionType: FunctionTypeSyntax) -> [ClosureParameter] {
    functionType.parameters.map { param in
        ClosureParameter(
            label: param.secondName?.text,
            type: param.type
        )
    }
}

// MARK: - Unimplemented Closure Generation

private func generateUnimplementedClosure(for property: ClosureProperty, structName: String) -> String {
    // Build operation signature string for error message
    let operationSignature = buildOperationSignature(for: property)

    // Generate underscore parameters to ignore all inputs
    let underscoreParams: String
    if property.parameters.isEmpty {
        underscoreParams = ""
    } else {
        underscoreParams = property.parameters.map { _ in "_" }.joined(separator: ", ")
    }

    // All unimplemented closures throw the error
    // Note: We always throw, which requires the closure to be `throws`
    // For non-throwing closures, this will cause a compile error if unimplemented is called
    // That's intentional - it surfaces the mismatch
    return """
    \(property.name): { \(underscoreParams) in
                    throw Witness.Unimplemented.Error(
                        witness: "\(structName)",
                        operation: "\(operationSignature)",
                        location: location
                    )
                }
    """
}

private func buildOperationSignature(for property: ClosureProperty) -> String {
    if property.parameters.isEmpty {
        return "\(property.name)()"
    }

    let labels = property.parameters.map { param in
        param.label ?? "_"
    }

    let labelString = labels.map { "\($0):" }.joined()
    return "\(property.name)(\(labelString))"
}

// MARK: - Diagnostics

enum UnimplementedDiagnostic: String, DiagnosticMessage {
    case requiresStruct
    case noClosureProperties

    var message: String {
        switch self {
        case .requiresStruct:
            return "@WitnessUnimplemented can only be applied to structs"
        case .noClosureProperties:
            return "@WitnessUnimplemented requires at least one closure property"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "WitnessUnimplementedMacro", id: rawValue)
    }

    var severity: DiagnosticSeverity { .error }
}
