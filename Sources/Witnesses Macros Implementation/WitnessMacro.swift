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

// MARK: - WitnessMacro

public struct WitnessMacro {}

// MARK: - Derive Options

/// Represents the derive modes specified in @Witness
struct DeriveOptions: OptionSet {
    let rawValue: UInt8

    static let mock = DeriveOptions(rawValue: 1 << 0)
    static let generator = DeriveOptions(rawValue: 1 << 1)
}

/// Parses derive options from the @Witness attribute arguments.
///
/// Handles:
/// - `@Witness` → empty options
/// - `@Witness(.mock)` → .mock
/// - `@Witness([.mock, .spy])` → [.mock, .spy]
private func parseDeriveOptions(from node: AttributeSyntax) -> DeriveOptions {
    guard let arguments = node.arguments,
          case .argumentList(let argList) = arguments,
          let firstArg = argList.first else {
        return []
    }

    var options: DeriveOptions = []

    // Handle single member access: .mock
    if let memberAccess = firstArg.expression.as(MemberAccessExprSyntax.self) {
        if let option = deriveOption(from: memberAccess.declName.baseName.text) {
            options.insert(option)
        }
    }
    // Handle array literal: [.mock, .spy]
    else if let arrayExpr = firstArg.expression.as(ArrayExprSyntax.self) {
        for element in arrayExpr.elements {
            if let memberAccess = element.expression.as(MemberAccessExprSyntax.self) {
                if let option = deriveOption(from: memberAccess.declName.baseName.text) {
                    options.insert(option)
                }
            }
        }
    }

    return options
}

private func deriveOption(from name: String) -> DeriveOptions? {
    switch name {
    case "mock": return .mock
    case "generator": return .generator
    default: return nil
    }
}

// MARK: - MemberMacro

extension WitnessMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Handle enum declarations
        if let enumDecl = declaration.as(EnumDeclSyntax.self) {
            return expandEnum(enumDecl: enumDecl, node: node, context: context)
        }

        // Handle struct declarations
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: node,
                message: WitnessDiagnostic.requiresStructOrEnum
            ))
            return []
        }

        return expandStruct(structDecl: structDecl, node: node, context: context)
    }

    private static func expandStruct(
        structDecl: StructDeclSyntax,
        node: AttributeSyntax,
        context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        let closureProperties = extractClosureProperties(from: structDecl)

        guard !closureProperties.isEmpty else {
            context.diagnose(Diagnostic(
                node: node,
                message: WitnessDiagnostic.noClosureProperties
            ))
            return []
        }

        var members: [DeclSyntax] = []

        // Compute shared values once
        let isPublic = structDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
        let inlinable = canInline(from: structDecl)
        let structName = structDecl.name.text
        let nonClosureProperties = extractNonClosureProperties(from: structDecl)
        // Generate public initializer if needed (skip if struct already has one)
        let hasExistingInit = structDecl.memberBlock.members.contains { member in
            member.decl.is(InitializerDeclSyntax.self)
        }
        if isPublic && !hasExistingInit {
            members.append(generatePublicInit(
                closureProperties: closureProperties,
                nonClosureProperties: nonClosureProperties,
                isPublic: isPublic
            ))
        }

        // Generate methods for labeled closures (skip optional closures — consumer calls directly)
        for property in closureProperties where property.hasLabels && !property.isOptional {
            if let method = generateMethod(for: property, inlinable: inlinable) {
                members.append(method)
            }
        }

        // Generate Action enum
        members.append(generateActionEnum(for: closureProperties))

        // Typealias for use in nested types (Observe) where bare struct name may not resolve
        if isPublic {
            members.append("public typealias _Witness = Self" as DeclSyntax)
        } else if inlinable {
            members.append("@usableFromInline typealias _Witness = Self" as DeclSyntax)
        } else {
            members.append("typealias _Witness = Self" as DeclSyntax)
        }

        // Generate Observe accessor struct and property
        members.append(generateObserveStruct(for: closureProperties, nonClosureProperties: nonClosureProperties, structName: structName, isPublic: isPublic, inlinable: inlinable))
        members.append(generateObserveProperty())

        // Generate unimplemented() as a member (not extension) for correct name resolution
        // in nested types where short names only resolve from the struct's parent scope
        members.append(generateUnimplementedMember(
            structName: structName,
            closureProperties: closureProperties,
            nonClosureProperties: nonClosureProperties,
            isPublic: isPublic,
            inlinable: inlinable
        ))

        // Generate mock() if .mock is specified
        let deriveOptions = parseDeriveOptions(from: node)
        if deriveOptions.contains(.mock) {
            members.append(generateMockMember(
                structName: structName,
                closureProperties: closureProperties,
                nonClosureProperties: nonClosureProperties,
                isPublic: isPublic,
                inlinable: inlinable
            ))
        }

        // Generate callAsFunction if .generator is specified and there's exactly one closure
        if deriveOptions.contains(.generator), closureProperties.count == 1 {
            let property = closureProperties[0]
            members.append(generateCallAsFunction(for: property, inlinable: inlinable))
            members.append(generateConstantMember(
                structName: structName,
                property: property,
                isPublic: isPublic,
                inlinable: inlinable
            ))
        }

        return members
    }

    private static func expandEnum(
        enumDecl: EnumDeclSyntax,
        node: AttributeSyntax,
        context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        let enumCases = extractEnumCases(from: enumDecl)

        guard !enumCases.isEmpty else {
            context.diagnose(Diagnostic(
                node: node,
                message: WitnessDiagnostic.noEnumCases
            ))
            return []
        }

        let enumName = enumDecl.name.text
        return generateEnumPrismMembers(for: enumCases, enumName: enumName)
    }
}

// MARK: - MemberAttributeMacro

extension WitnessMacro: MemberAttributeMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        // No attributes for enum members
        if declaration.is(EnumDeclSyntax.self) {
            return []
        }

        guard let varDecl = member.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              binding.accessorBlock == nil,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation else {
            return []
        }

        var attributes: [AttributeSyntax] = []

        // For public structs, add @usableFromInline to non-public stored properties
        // so that @inlinable generated code (Observe, unimplemented) can reference them.
        // Skip for properties with restricted access (package/private/fileprivate) —
        // @usableFromInline is incompatible with those access levels.
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            let isPublicStruct = structDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
            let isPublicMember = varDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
            if isPublicStruct && !isPublicMember && !hasRestrictedAccess(varDecl.modifiers) {
                attributes.append(AttributeSyntax(stringLiteral: "@usableFromInline"))
            }
        }

        // Only deprecate closures with labeled parameters; skip optional closures
        // (they have no generated convenience method to deprecate in favor of)
        let isOptionalClosure = typeAnnotation.type.as(OptionalTypeSyntax.self) != nil
        if !isOptionalClosure, let functionType = extractFunctionType(from: typeAnnotation.type) {
            let hasLabels = functionType.parameters.contains { param in
                param.secondName != nil ||
                (param.firstName != nil && param.firstName?.tokenKind != .wildcard)
            }

            if hasLabels {
                let rawName = identifier.identifier.text
                let strippedName = rawName.hasPrefix("_") ? String(rawName.dropFirst()) : rawName
                let methodSignature = generateMethodSignature(
                    name: strippedName,
                    functionType: functionType
                )
                let attributeString = "@available(*, deprecated, message: \"Use '\(methodSignature)' instead\")"
                attributes.append(AttributeSyntax(stringLiteral: attributeString))
            }
        }

        return attributes
    }
}

// MARK: - ExtensionMacro

extension WitnessMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        var extensions: [ExtensionDeclSyntax] = []

        // All @Witness types conform to __WitnessProtocol (skip if already declared)
        let alreadyConformsToWitnessProtocol = declaration.inheritanceClause?.inheritedTypes.contains { inherited in
            let text = inherited.type.trimmedDescription
            return text == "__WitnessProtocol" || text == "Witness.`Protocol`" || text == "Witness.Protocol" || text.hasSuffix(".__WitnessProtocol")
        } ?? false

        if !alreadyConformsToWitnessProtocol {
            let witnessExt = try ExtensionDeclSyntax("extension \(type.trimmed): Witness_Primitives.__WitnessProtocol {}")
            extensions.append(witnessExt)
        }

        // Enums also conform to Optic.Prism.Accessible for composition support
        // Uses hoisted __OpticPrismAccessible since Optic.Prism.Accessible is a typealias
        if declaration.is(EnumDeclSyntax.self) {
            let prismExt = try ExtensionDeclSyntax("extension \(type.trimmed): Optic_Primitives.__OpticPrismAccessible {}")
            extensions.append(prismExt)
        }

        // unimplemented(), mock(), constant() are generated as members (MemberMacro)
        // to ensure correct name resolution for nested types

        return extensions
    }

}

// MARK: - Unimplemented Member Generation

private func generateUnimplementedMember(
    structName: String,
    closureProperties: [ClosureProperty],
    nonClosureProperties: [NonClosureProperty],
    isPublic: Bool,
    inlinable: Bool = true
) -> DeclSyntax {
    let accessModifier = isPublic ? "public " : ""
    let inlinableAttr = inlinable ? "@inlinable\n    " : ""

    // Check if any closure can throw Witness.Unimplemented.Error (needs Source.Location)
    let needsSourceLocation = closureProperties.contains { property in
        property.isThrowing && (
            property.throwsType == nil ||
            property.throwsType?.trimmedDescription == "Witness.Unimplemented.Error"
        )
    }

    // Generate closure initializers
    let closureInits = closureProperties.map { property in
        generateUnimplementedClosure(for: property, structName: structName, isPublic: isPublic)
    }.joined(separator: ",\n            ")

    // Build parameter list: non-closure params first, then source location defaults (if needed)
    let nonClosureParamList = nonClosureProperties.map { "\($0.name): \($0.type)" }
    var paramParts = nonClosureParamList
    if needsSourceLocation {
        paramParts += [
            "fileID: Swift.String = #fileID",
            "filePath: Swift.String = #filePath",
            "line: Int = #line",
            "column: Int = #column"
        ]
    }
    let allParams = paramParts.joined(separator: ",\n        ")

    let allInits = joinInitArguments(nonClosureProperties: nonClosureProperties, closureInits: closureInits)

    let locationCode = needsSourceLocation
        ? "\n        let location = Source.Location(fileID: fileID, filePath: filePath, line: line, column: column)"
        : ""

    return """
    /// Creates an unimplemented witness where all operations fatal error or throw.
    ///
    /// Use this in tests to start with a placeholder and override only what you need:
    /// ```swift
    /// var api = \(raw: structName).unimplemented()
    /// api.fetch = { id in "mocked result" }
    /// ```
    \(raw: inlinableAttr)\(raw: accessModifier)static func unimplemented(
        \(raw: allParams)
    ) -> Self {\(raw: locationCode)
        return Self(
            \(raw: allInits)
        )
    }
    """
}

// MARK: - Mock Member Generation

private func generateMockMember(
    structName: String,
    closureProperties: [ClosureProperty],
    nonClosureProperties: [NonClosureProperty],
    isPublic: Bool,
    inlinable: Bool = true
) -> DeclSyntax {
    let accessModifier = isPublic ? "public " : ""
    let inlinableAttr = inlinable ? "@inlinable\n    " : ""

    // Optional closures excluded from mock parameters — consumer never sees them
    let mockParameters = closureProperties.compactMap { property -> String? in
        property.isOptional ? nil : generateMockParameter(for: property)
    }

    let nonClosureParamList = nonClosureProperties.map { "\($0.name): \($0.type)" }
    let allParams = (nonClosureParamList + mockParameters)
        .joined(separator: ",\n        ")

    let closureInits = closureProperties.map { property in
        generateMockClosure(for: property, isPublic: isPublic)
    }.joined(separator: ",\n            ")

    let allInits = joinInitArguments(nonClosureProperties: nonClosureProperties, closureInits: closureInits)

    return """
    /// Creates a mock witness with fixed return values.
    ///
    /// This is useful for tests where you want simple, predictable values:
    /// ```swift
    /// let api = \(raw: structName).mock(fetchUser: testUser)
    /// ```
    ///
    /// For Void-returning operations, the parameter defaults to `()`.
    \(raw: inlinableAttr)\(raw: accessModifier)static func mock(
        \(raw: allParams)
    ) -> Self {
        Self(
            \(raw: allInits)
        )
    }
    """
}

// MARK: - Init Argument Joining

private func joinInitArguments(
    nonClosureProperties: [NonClosureProperty],
    closureInits: String
) -> String {
    let nonClosureInits = nonClosureProperties.map { "\($0.name): \($0.name)" }
    if nonClosureInits.isEmpty {
        return closureInits
    }
    return nonClosureInits.joined(separator: ",\n            ") + ",\n            " + closureInits
}

// MARK: - Constant Member Generation

private func generateConstantMember(
    structName: String,
    property: ClosureProperty,
    isPublic: Bool,
    inlinable: Bool = true
) -> DeclSyntax {
    let accessModifier = isPublic ? "public " : ""
    let inlinableAttr = inlinable ? "@inlinable\n    " : ""
    let initLabel = property.initLabel(isPublic: isPublic)
    let returnType = property.returnType.trimmedDescription
    let throwsAnnotation = property.throwsAnnotation

    let closureParams = property.closureParameterList(named: false)
    let closureBody = "{ \(closureParams) \(throwsAnnotation)-> \(returnType) in value }"

    return """
    /// Creates a generator that always returns the given value.
    ///
    /// ```swift
    /// let generator = \(raw: structName).constant(fixedValue)
    /// print(generator())  // fixedValue
    /// print(generator())  // fixedValue
    /// ```
    \(raw: inlinableAttr)\(raw: accessModifier)static func constant(_ value: \(raw: returnType)) -> Self {
        Self(\(raw: initLabel): \(raw: closureBody))
    }
    """
}

// MARK: - Mock Generation Helpers

/// Generates a mock() parameter for a closure property.
/// - Void return types get a default value of `()`
/// - Non-Void return types are required parameters
private func generateMockParameter(for property: ClosureProperty) -> String {
    let returnType = property.returnType.trimmedDescription

    if property.returnsVoid {
        return "\(property.methodName): Void = ()"
    } else {
        return "\(property.methodName): \(returnType)"
    }
}

/// Generates a mock closure initializer that returns the mock value.
private func generateMockClosure(for property: ClosureProperty, isPublic: Bool) -> String {
    let initLabel = property.initLabel(isPublic: isPublic)
    if property.isOptional { return "\(initLabel): nil" }
    let returnType = property.returnType.trimmedDescription
    let throwsAnnotation = property.throwsAnnotation
    let closureParams = property.closureParameterList(named: false)

    let body = property.returnsVoid ? "" : " \(property.methodName) "
    return "\(initLabel): { \(closureParams) \(throwsAnnotation)-> \(returnType) in\(body)}"
}

// MARK: - Property Extraction

struct ClosureProperty {
    let name: String
    let functionType: FunctionTypeSyntax
    let parameters: [ClosureParameter]
    let hasLabels: Bool
    let isAsync: Bool
    let isThrowing: Bool
    /// The typed error type if present (e.g., "MyError" from "throws(MyError)")
    let throwsType: TypeSyntax?
    let returnType: TypeSyntax
    /// The original type annotation (source of truth for optionality, attributes).
    let originalType: TypeSyntax
    /// Whether the closure property is optional (e.g., `(@Sendable () -> Void)?`).
    let isOptional: Bool

    /// The public method name: strips leading `_` from `name`.
    var methodName: String {
        if name.hasPrefix("_") {
            return String(name.dropFirst())
        }
        return name
    }

    /// The typed throws annotation string for use in closure/method signatures.
    /// e.g., "throws(Witness.Unimplemented.Error) " or "throws " or ""
    /// Trailing space included when non-empty.
    var throwsAnnotation: String {
        if let throwsType = throwsType {
            return "throws(\(throwsType.trimmedDescription)) "
        } else if isThrowing {
            return "throws "
        } else {
            return ""
        }
    }

    /// Whether the return type is Void.
    var returnsVoid: Bool {
        let rt = returnType.trimmedDescription
        return rt == "Void" || rt == "()"
    }

    /// The init label: for public structs, strips leading `_`; for non-public, uses raw name.
    func initLabel(isPublic: Bool) -> String {
        isPublic ? methodName : name
    }

    /// Effect specifiers for method signatures: " async throws(E)" or " async" or "".
    /// Leading space included when non-empty.
    var effectSpecifiers: String {
        var specs: [String] = []
        if isAsync { specs.append("async") }
        if isThrowing {
            if let throwsType = throwsType {
                specs.append("throws(\(throwsType.trimmedDescription))")
            } else {
                specs.append("throws")
            }
        }
        return specs.isEmpty ? "" : " " + specs.joined(separator: " ")
    }

    /// "await " prefix for call sites, or "".
    var awaitPrefix: String {
        isAsync ? "await " : ""
    }

    /// "try " prefix for call sites, or "".
    var tryPrefix: String {
        isThrowing ? "try " : ""
    }

    /// Return clause for method signatures: " -> T" or "" for Void.
    var returnClause: String {
        returnsVoid ? "" : " -> \(returnType)"
    }

    /// Closure parameter list with ownership annotations.
    /// `named: true` produces `(name: inout Base, name: consuming Base)` — for observe closures.
    /// `named: false` produces `(_, _)` — for unimplemented/mock closures.
    func closureParameterList(named: Bool) -> String {
        if parameters.isEmpty { return "()" }
        if !named {
            let underscores = parameters.map { _ in "_" }.joined(separator: ", ")
            return "(\(underscores))"
        }
        let parts = parameters.enumerated().map { index, param in
            let n = param.label ?? "p\(index)"
            if param.isInout {
                return "\(n): inout \(param.baseType)"
            } else if let ownership = param.ownership {
                return "\(n): \(ownership) \(param.baseType)"
            }
            return n
        }
        return "(\(parts.joined(separator: ", ")))"
    }

    /// Call-site argument list: "&name" for inout, "consume name" for consuming, plain otherwise.
    var callArgumentList: String {
        parameters.enumerated().map { index, param in
            let n = param.label ?? "p\(index)"
            if param.isInout { return "&\(n)" }
            if param.ownership == .consuming { return "consume \(n)" }
            return n
        }.joined(separator: ", ")
    }

    /// Formal parameter list for method signatures: "label p0: Type, ..."
    var methodParameterList: String {
        parameters.enumerated().map { index, param in
            let label = param.label ?? "_"
            let internalName = "p\(index)"
            return "\(label) \(internalName): \(param.type)"
        }.joined(separator: ", ")
    }

    /// Call arguments using positional names (p0, p1, ...) with & prefix for inout.
    var positionalCallArguments: String {
        parameters.enumerated().map { index, param in
            let prefix = param.isInout ? "&" : ""
            return "\(prefix)p\(index)"
        }.joined(separator: ", ")
    }
}

struct ClosureParameter {
    let label: String?
    let internalName: String
    let type: TypeSyntax
    let isInout: Bool
    /// `.borrowing` or `.consuming`, `nil` for default/`inout`
    let ownership: Keyword?

    /// Whether this parameter has an explicit ownership annotation (`borrowing`/`consuming`/`inout`).
    /// Parameters with ownership annotations are omitted from Action enum associated values.
    var hasOwnershipAnnotation: Bool {
        isInout || ownership != nil
    }

    /// The base type without ownership specifiers (`inout`/`borrowing`/`consuming`).
    var baseType: TypeSyntax {
        if hasOwnershipAnnotation,
           let attributed = type.as(AttributedTypeSyntax.self) {
            return attributed.baseType
        }
        return type
    }
}

/// Whether the declaration has restricted access (package, private, or fileprivate).
private func hasRestrictedAccess(_ modifiers: DeclModifierListSyntax) -> Bool {
    modifiers.contains {
        $0.name.tokenKind == .keyword(.package) ||
        $0.name.tokenKind == .keyword(.private) ||
        $0.name.tokenKind == .keyword(.fileprivate)
    }
}

/// Whether all stored properties in the struct are publicly accessible.
/// When false, generated members cannot be @inlinable (they reference private storage).
private func canInline(from structDecl: StructDeclSyntax) -> Bool {
    structDecl.memberBlock.members.allSatisfy { member in
        guard let varDecl = member.decl.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              binding.accessorBlock == nil else { return true }
        return !hasRestrictedAccess(varDecl.modifiers)
    }
}

private func extractClosureProperties(from structDecl: StructDeclSyntax) -> [ClosureProperty] {
    var properties: [ClosureProperty] = []

    for member in structDecl.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self),
              (varDecl.bindingSpecifier.tokenKind == .keyword(.var) ||
               varDecl.bindingSpecifier.tokenKind == .keyword(.let)),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation,
              let functionType = extractFunctionType(from: typeAnnotation.type) else {
            continue
        }

        let parameters = extractParameters(from: functionType)
        let hasLabels = parameters.contains { $0.label != nil }

        // Extract the typed error type from throws clause
        let throwsType: TypeSyntax? = functionType.effectSpecifiers?.throwsClause?.type

        properties.append(ClosureProperty(
            name: identifier.identifier.text,
            functionType: functionType,
            parameters: parameters,
            hasLabels: hasLabels,
            isAsync: functionType.effectSpecifiers?.asyncSpecifier != nil,
            isThrowing: functionType.effectSpecifiers?.throwsClause != nil,
            throwsType: throwsType,
            returnType: functionType.returnClause.type,
            originalType: typeAnnotation.type,
            isOptional: typeAnnotation.type.as(OptionalTypeSyntax.self) != nil
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

    // Optional type (e.g., `(@Sendable () -> Void)?`)
    if let optional = type.as(OptionalTypeSyntax.self) {
        return extractFunctionType(from: optional.wrappedType)
    }

    // Parenthesized tuple type (e.g., `(@Sendable () -> Void)` in `(@Sendable () -> Void)?`)
    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let element = tuple.elements.first {
        return extractFunctionType(from: element.type)
    }

    return nil
}

private func extractParameters(from functionType: FunctionTypeSyntax) -> [ClosureParameter] {
    var parameters: [ClosureParameter] = []

    for (index, param) in functionType.parameters.enumerated() {
        let label: String? = {
            if let second = param.secondName?.text {
                return second
            }
            if let first = param.firstName?.text, first != "_" {
                return first
            }
            return nil
        }()
        let internalName = label ?? "p\(index)"

        var isInout = false
        var ownership: Keyword? = nil

        if let attributed = param.type.as(AttributedTypeSyntax.self) {
            for specifier in attributed.specifiers {
                if let simple = specifier.as(SimpleTypeSpecifierSyntax.self) {
                    switch simple.specifier.tokenKind {
                    case .keyword(.inout):
                        isInout = true
                    case .keyword(.borrowing):
                        ownership = .borrowing
                    case .keyword(.consuming):
                        ownership = .consuming
                    default:
                        break
                    }
                }
            }
        }

        parameters.append(ClosureParameter(
            label: label,
            internalName: internalName,
            type: param.type,
            isInout: isInout,
            ownership: ownership
        ))
    }

    return parameters
}

// MARK: - Public Init Generation

private func generatePublicInit(
    closureProperties: [ClosureProperty],
    nonClosureProperties: [NonClosureProperty],
    isPublic: Bool
) -> DeclSyntax {
    var initParameters: [String] = []
    var assignments: [String] = []

    // Non-closure properties first
    for prop in nonClosureProperties {
        initParameters.append("\(prop.name): \(prop.type)")
        assignments.append("self.\(prop.name) = \(prop.name)")
    }

    // Closure properties
    for prop in closureProperties {
        let label = prop.initLabel(isPublic: isPublic)
        if prop.isOptional {
            // Optional closures: no @escaping, default nil
            initParameters.append("\(label): \(prop.originalType.trimmedDescription) = nil")
        } else {
            // Use originalType to preserve @Sendable and other attributes.
            // @escaping is prepended since closure parameters in init are non-escaping by default.
            initParameters.append("\(label): @escaping \(prop.originalType.trimmedDescription)")
        }
        if label != prop.name {
            assignments.append("self.\(prop.name) = \(label)")
        } else {
            assignments.append("self.\(prop.name) = \(prop.name)")
        }
    }

    let parameterList = initParameters.joined(separator: ",\n        ")
    let assignmentList = assignments.joined(separator: "\n        ")

    return """
        public init(
            \(raw: parameterList)
        ) {
            \(raw: assignmentList)
        }
        """
}

// MARK: - Method Generation

private func generateMethod(for property: ClosureProperty, inlinable: Bool = true) -> DeclSyntax? {
    guard property.hasLabels, !property.isOptional else { return nil }
    let inlinableAttr = inlinable ? "@inlinable\n        " : ""

    return """
        \(raw: inlinableAttr)public func \(raw: property.methodName)(\(raw: property.methodParameterList))\(raw: property.effectSpecifiers)\(raw: property.returnClause) {
            \(raw: property.tryPrefix)\(raw: property.awaitPrefix)self.\(raw: property.name)(\(raw: property.positionalCallArguments))
        }
        """
}

/// Generates callAsFunction() for .generator derive mode.
private func generateCallAsFunction(for property: ClosureProperty, inlinable: Bool = true) -> DeclSyntax {
    let inlinableAttr = inlinable ? "@inlinable\n        " : ""
    return """
        \(raw: inlinableAttr)public func callAsFunction(\(raw: property.methodParameterList))\(raw: property.effectSpecifiers)\(raw: property.returnClause) {
            \(raw: property.tryPrefix)\(raw: property.awaitPrefix)self.\(raw: property.name)(\(raw: property.positionalCallArguments))
        }
        """
}

private func generateMethodSignature(name: String, functionType: FunctionTypeSyntax) -> String {
    let labels = functionType.parameters.enumerated().map { index, param in
        if let second = param.secondName?.text { return second }
        if let first = param.firstName?.text, first != "_" { return first }
        return "_"
    }

    if labels.isEmpty {
        return "\(name)()"
    }

    let labelString = labels.map { "\($0):" }.joined()
    return "\(name)(\(labelString))"
}

// MARK: - Action Enum Generation

private func generateActionEnum(for properties: [ClosureProperty]) -> DeclSyntax {
    let actionCases = generateActionCases(for: properties)
    let caseEnum = generateCaseEnum(for: properties)
    let caseProperty = generateActionCaseProperty(for: properties)
    let resultEnum = generateResultEnum(for: properties)
    let prismProperties = generatePrismProperties(for: properties)

    return """
        public enum Action: Sendable {
            \(raw: actionCases)

            /// The enumerable case discriminant (without associated values).
            \(raw: caseEnum)

            /// This action's case discriminant.
            \(raw: caseProperty)

            /// Typed result for each action, preserving the specific success and error types.
            \(raw: resultEnum)

            /// An action paired with its typed result.
            public struct Outcome: ~Copyable, Sendable {
                public let action: Action
                public let result: Result

                @inlinable
                public init(action: Action, result: consuming Result) {
                    self.action = action
                    self.result = result
                }

                @usableFromInline
                consuming func __consumeResult() -> Result { result }
            }

            /// Prisms for each action case, enabling type-safe case matching and extraction.
            public struct Prisms: Sendable {
                @inlinable
                public init() {}

                \(raw: prismProperties)
            }

            /// Access prisms for each action case.
            @inlinable
            public static var prisms: Prisms { Prisms() }

            /// Checks if this action matches the given prism.
            @inlinable
            public func `is`<Value>(_ keyPath: KeyPath<Prisms, Optic_Primitives.Optic.Prism<Action, Value>>) -> Bool {
                Self.prisms[keyPath: keyPath].extract(self) != nil
            }

            /// Extracts the associated value for the given prism, if this action matches.
            @inlinable
            public subscript<Value>(prism keyPath: KeyPath<Prisms, Optic_Primitives.Optic.Prism<Action, Value>>) -> Value? {
                Self.prisms[keyPath: keyPath].extract(self)
            }
        }
        """
}

/// Generates the case declarations for the Action enum.
private func generateActionCases(for properties: [ClosureProperty]) -> String {
    properties.map { property in
        let copyableParams = property.parameters.filter { !$0.hasOwnershipAnnotation }
        if copyableParams.isEmpty {
            return "case \(property.methodName)"
        }
        let assocValues = copyableParams.map { param in
            if let label = param.label {
                return "\(label): \(param.baseType)"
            }
            return "\(param.baseType)"
        }.joined(separator: ", ")
        return "case \(property.methodName)(\(assocValues))"
    }.joined(separator: "\n            ")
}

/// Generates the Case enum (Finite.Enumerable discriminant without associated values).
private func generateCaseEnum(for properties: [ClosureProperty]) -> String {
    let caseCount = properties.count
    let caseCases = properties.map { "case \($0.methodName)" }.joined(separator: "\n                ")
    let ordinalCases = properties.enumerated().map { i, p in
        "case .\(p.methodName): Ordinal_Primitives.Ordinal(\(i))"
    }.joined(separator: "\n                    ")

    let initCases: String
    if properties.count == 1 {
        initCases = "default: self = .\(properties[0].methodName)"
    } else {
        let explicit = properties.dropLast().enumerated().map { i, p in
            "case \(i): self = .\(p.methodName)"
        }.joined(separator: "\n                    ")
        initCases = explicit + "\n                    default: self = .\(properties.last!.methodName)"
    }

    return """
    public enum Case: Finite_Primitives.Finite.Enumerable, Sendable {
                \(caseCases)

                @inlinable
                public static var count: Cardinal_Primitives.Cardinal { Cardinal_Primitives.Cardinal(\(caseCount)) }

                @inlinable
                public var ordinal: Ordinal_Primitives.Ordinal {
                    switch self {
                    \(ordinalCases)
                    }
                }

                @inlinable
                public init(__unchecked: Void, ordinal: Ordinal_Primitives.Ordinal) {
                    switch ordinal.rawValue {
                    \(initCases)
                    }
                }
            }
    """
}

/// Generates the Action → Case property.
private func generateActionCaseProperty(for properties: [ClosureProperty]) -> String {
    let cases = properties.map { "case .\($0.methodName): .\($0.methodName)" }
        .joined(separator: "\n                ")
    return """
    @inlinable
            public var `case`: Case {
                switch self {
                \(cases)
                }
            }
    """
}

/// Generates the Result enum with Standard_Library_Extensions.Result<Success, Failure> per action.
private func generateResultEnum(for properties: [ClosureProperty]) -> String {
    let cases = properties.map { property in
        generateTypedResultCase(for: property)
    }.joined(separator: "\n                ")
    return """
    public enum Result: ~Copyable, Sendable {
                \(cases)
            }
    """
}

/// Generates a typed Result case for a closure property.
/// e.g., `case fetchUser(Standard_Library_Extensions.Result<String, Witness.Unimplemented.Error>)`
private func generateTypedResultCase(for property: ClosureProperty) -> String {
    let returnType = property.returnType.trimmedDescription
    let errorType = property.throwsType?.trimmedDescription ?? "Never"
    return "case \(property.methodName)(Standard_Library_Extensions.Result<\(returnType), \(errorType)>)"
}

/// Generates prism properties for each closure property.
private func generatePrismProperties(for properties: [ClosureProperty]) -> String {
    properties.map { property in
        generatePrismProperty(for: property)
    }.joined(separator: "\n\n                ")
}

/// Generates a single prism property for a closure property.
/// Only Copyable (non-owned) parameters appear in the prism type.
private func generatePrismProperty(for property: ClosureProperty) -> String {
    let copyableParams = property.parameters.filter { !$0.hasOwnershipAnnotation }
    let prismCase = PrismCase(
        caseName: property.methodName,
        rootTypeName: "Action",
        parameters: copyableParams.map { ($0.label, $0.baseType.trimmedDescription) }
    )
    return generatePrism(for: prismCase)
}

// MARK: - Non-Closure Property Extraction

struct NonClosureProperty {
    let name: String
    let type: String
}

private func extractNonClosureProperties(from structDecl: StructDeclSyntax) -> [NonClosureProperty] {
    var properties: [NonClosureProperty] = []
    for member in structDecl.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              binding.accessorBlock == nil,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation,
              extractFunctionType(from: typeAnnotation.type) == nil else {
            continue
        }
        properties.append(NonClosureProperty(
            name: identifier.identifier.text,
            type: typeAnnotation.type.trimmedDescription
        ))
    }
    return properties
}

// MARK: - Unimplemented Closure Generation

private func generateUnimplementedClosure(for property: ClosureProperty, structName: String, isPublic: Bool) -> String {
    let initLabel = property.initLabel(isPublic: isPublic)

    // Optional closures: nil is the unimplemented state
    if property.isOptional { return "\(initLabel): nil" }

    let operationSignature = buildOperationSignature(for: property)
    let throwsAnnotation = property.throwsAnnotation

    let returnType = property.returnType.trimmedDescription
    let hasConsumingParams = property.parameters.contains { $0.ownership == .consuming }

    // Can only throw Witness.Unimplemented.Error when the closure's error type matches
    let canThrowUnimplemented = property.isThrowing && (
        property.throwsType == nil ||
        property.throwsType?.trimmedDescription == "Witness.Unimplemented.Error"
    )
    let needsFatalError = !canThrowUnimplemented

    // Generate closure parameter list.
    // Consuming params need named bindings when using fatalError (so they can be consumed).
    let closureStart: String
    if property.parameters.isEmpty {
        closureStart = "{ () \(throwsAnnotation)-> \(returnType) in"
    } else if needsFatalError && hasConsumingParams {
        let paramBindings = property.parameters.enumerated().map { index, param in
            if param.ownership == .consuming {
                return "p\(index): consuming \(param.baseType)"
            }
            return "_"
        }.joined(separator: ", ")
        closureStart = "{ (\(paramBindings)) \(throwsAnnotation)-> \(returnType) in"
    } else {
        let underscoreParams = property.parameters.map { _ in "_" }.joined(separator: ", ")
        closureStart = "{ (\(underscoreParams)) \(throwsAnnotation)-> \(returnType) in"
    }

    if canThrowUnimplemented {
        // Throwing closures with compatible error type: throw Witness.Unimplemented.Error
        return """
\(initLabel): \(closureStart)
                throw Witness.Unimplemented.Error(
                    witness: "\(structName)",
                    operation: "\(operationSignature)",
                    location: location
                )
            }
"""
    } else if hasConsumingParams {
        // Non-throwing with consuming params: consume then fatalError
        let consumeStatements = property.parameters.enumerated().compactMap { index, param -> String? in
            guard param.ownership == .consuming else { return nil }
            return "_ = consume p\(index)"
        }.joined(separator: "\n                ")
        return """
\(initLabel): \(closureStart)
                \(consumeStatements)
                fatalError("\\(Self.self).\\(#function) is unimplemented")
            }
"""
    } else {
        // Non-throwing, no consuming params: just fatalError
        return """
\(initLabel): \(closureStart)
                fatalError("\\(Self.self).\\(#function) is unimplemented")
            }
"""
    }
}

private func buildOperationSignature(for property: ClosureProperty) -> String {
    if property.parameters.isEmpty {
        return "\(property.methodName)()"
    }

    let labels = property.parameters.map { param in
        param.label ?? "_"
    }

    let labelString = labels.map { "\($0):" }.joined()
    return "\(property.methodName)(\(labelString))"
}

// MARK: - Observe Accessor Generation

private func generateObserveStruct(for properties: [ClosureProperty], nonClosureProperties: [NonClosureProperty], structName: String, isPublic: Bool, inlinable: Bool = true) -> DeclSyntax {
    // Non-closure property pass-through from witness
    let nonClosurePassthrough = nonClosureProperties.map { "\($0.name): witness.\($0.name)" }

    // Generate observe closures for each variant
    let bothClosures = properties.map {
        generateObserveClosure(for: $0, variant: .both, isPublic: isPublic)
    }
    let beforeClosures = properties.map {
        generateObserveClosure(for: $0, variant: .before, isPublic: isPublic)
    }
    let afterClosures = properties.map {
        generateObserveClosure(for: $0, variant: .after, isPublic: isPublic)
    }

    let bothInitArgs = (nonClosurePassthrough + bothClosures).joined(separator: ",\n                    ")
    let beforeInitArgs = (nonClosurePassthrough + beforeClosures).joined(separator: ",\n                    ")
    let afterInitArgs = (nonClosurePassthrough + afterClosures).joined(separator: ",\n                    ")

    let ufiAttr = inlinable ? "@usableFromInline\n            " : ""
    let inlinableAttr = inlinable ? "@inlinable\n            " : ""

    return """
        public struct Observe: Sendable {
            \(raw: ufiAttr)internal let witness: _Witness

            \(raw: ufiAttr)internal init(_ witness: _Witness) {
                self.witness = witness
            }

            \(raw: inlinableAttr)public func callAsFunction(
                _ before: @escaping @Sendable (Action) -> Void,
                after: @escaping @Sendable (borrowing Action.Outcome) -> Void
            ) -> _Witness {
                _Witness(
                    \(raw: bothInitArgs)
                )
            }

            \(raw: inlinableAttr)public func before(
                _ observer: @escaping @Sendable (Action) -> Void
            ) -> _Witness {
                _Witness(
                    \(raw: beforeInitArgs)
                )
            }

            \(raw: inlinableAttr)public func after(
                _ observer: @escaping @Sendable (borrowing Action.Outcome) -> Void
            ) -> _Witness {
                _Witness(
                    \(raw: afterInitArgs)
                )
            }
        }
        """
}

private func generateObserveProperty() -> DeclSyntax {
    return """
        public var observe: Observe {
            Observe(self)
        }
        """
}

private enum ObserveVariant {
    case before
    case after
    case both
}

private func generateObserveClosure(
    for property: ClosureProperty,
    variant: ObserveVariant,
    isPublic: Bool
) -> String {
    let initLabel = property.initLabel(isPublic: isPublic)
    let closureParams = property.closureParameterList(named: true)
    let callArgs = property.callArgumentList
    let returnType = property.returnType.trimmedDescription
    let throwsAnno = property.isThrowing ? property.throwsAnnotation : ""

    // For optional closures: wrap in .map { _original -> ClosureType in { ... } }
    // The inner closure calls _original instead of witness.propertyName.
    // Explicit return type on .map closure resolves "ambiguous without type annotation" in _Witness(...) init.
    if property.isOptional {
        let innerBody = generateObserveBody(
            for: property,
            variant: variant,
            callExpression: "_original(\(callArgs))"
        )
        // Use the unwrapped originalType (includes @Sendable) for the .map return annotation.
        // originalType is e.g. `(@Sendable () -> Void)?`, wrappedType is `(@Sendable () -> Void)`.
        let wrappedType = property.originalType.as(OptionalTypeSyntax.self)?.wrappedType.trimmedDescription
            ?? property.functionType.trimmedDescription
        return """
        \(initLabel): witness.\(property.name).map { _original -> \(wrappedType) in
                        { \(closureParams) \(throwsAnno)-> \(returnType) in
                    \(innerBody)
                        }
                    }
        """
    }

    let body = generateObserveBody(
        for: property,
        variant: variant,
        callExpression: "witness.\(property.name)(\(callArgs))"
    )

    return """
    \(initLabel): { [witness] \(closureParams) \(throwsAnno)-> \(returnType) in
    \(body)
                }
    """
}

/// Generates the body of an observe closure, parameterized by the call expression.
/// `callExpression` is either `"witness.propertyName(args)"` (normal) or `"_original(args)"` (optional .map).
private func generateObserveBody(
    for property: ClosureProperty,
    variant: ObserveVariant,
    callExpression: String
) -> String {
    let actionConstruction = formatActionConstruction(for: property)
    let returnType = property.returnType.trimmedDescription
    let hasReturn = !property.returnsVoid
    let errorType = property.throwsType?.trimmedDescription ?? "Never"
    let witnessResultType = "Standard_Library_Extensions.Result<\(returnType), \(errorType)>"

    let beforeCall: String
    let afterCall: String
    switch variant {
    case .before:
        beforeCall = "observer"
        afterCall = ""
    case .after:
        beforeCall = ""
        afterCall = "observer"
    case .both:
        beforeCall = "before"
        afterCall = "after"
    }

    func outcomeExpr(witnessResult: String) -> String {
        "Action.Outcome(action: action, result: Action.Result.\(property.methodName)(\(witnessResult)))"
    }

    switch variant {
    case .before:
        let returnKeyword = hasReturn ? "return " : ""
        return """
                        \(beforeCall)(\(actionConstruction))
                        \(returnKeyword)\(property.tryPrefix)\(property.awaitPrefix)\(callExpression)
        """

    case .after where property.isThrowing, .both where property.isThrowing:
        let beforeLine = variant == .both
            ? "\(beforeCall)(action)\n                        "
            : ""
        let successBody: String
        if hasReturn {
            successBody = """
            let __outcome = \(outcomeExpr(witnessResult: "\(witnessResultType).success(result)"))
                                \(afterCall)(__outcome)
                                let __result = __outcome.__consumeResult()
                                switch consume __result {
                                case .\(property.methodName)(.success(let __value)): return __value
                                default: fatalError("unreachable")
                                }
            """
        } else {
            successBody = """
            let __outcome = \(outcomeExpr(witnessResult: "\(witnessResultType).success(())"))
                                \(afterCall)(__outcome)
            """
        }
        let doThrowsType = property.throwsType?.trimmedDescription ?? "any Error"
        return """
                        let action: Action = \(actionConstruction)
                        \(beforeLine)do throws(\(doThrowsType)) {
                            \(hasReturn ? "let result = " : "")try \(property.awaitPrefix)\(callExpression)
                            \(successBody)
                        } catch {
                            let __outcome = \(outcomeExpr(witnessResult: "\(witnessResultType).failure(error)"))
                            \(afterCall)(__outcome)
                            throw error
                        }
        """

    case .after, .both:
        let beforeLine = variant == .both
            ? "\(beforeCall)(action)\n                        "
            : ""
        let resultBody: String
        if hasReturn {
            resultBody = """
            let __outcome = \(outcomeExpr(witnessResult: "\(witnessResultType).success(result)"))
                        \(afterCall)(__outcome)
                        let __result = __outcome.__consumeResult()
                        switch consume __result {
                        case .\(property.methodName)(.success(let __value)): return __value
                        default: fatalError("unreachable")
                        }
            """
        } else {
            resultBody = """
            let __outcome = \(outcomeExpr(witnessResult: "\(witnessResultType).success(())"))
                        \(afterCall)(__outcome)
            """
        }
        return """
                        let action: Action = \(actionConstruction)
                        \(beforeLine)\(hasReturn ? "let result = " : "")\(property.awaitPrefix)\(callExpression)
                        \(resultBody)
        """
    }
}

/// Formats action construction: `.propertyName` or `.propertyName(label: value, ...)`
/// Only includes Copyable (non-owned) parameters in the Action construction.
private func formatActionConstruction(for property: ClosureProperty) -> String {
    let copyableParams = property.parameters.filter { !$0.hasOwnershipAnnotation }
    if copyableParams.isEmpty {
        return ".\(property.methodName)"
    }
    let args = copyableParams.map { param in
        let name = param.internalName
        if let label = param.label {
            return "\(label): \(name)"
        } else {
            return name
        }
    }.joined(separator: ", ")
    return ".\(property.methodName)(\(args))"
}

// MARK: - Diagnostics

enum WitnessDiagnostic: String, DiagnosticMessage {
    case requiresStructOrEnum
    case noClosureProperties
    case noEnumCases

    var message: String {
        switch self {
        case .requiresStructOrEnum:
            return "@Witness can only be applied to structs or enums"
        case .noClosureProperties:
            return "@Witness requires at least one closure property"
        case .noEnumCases:
            return "@Witness requires at least one enum case"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "WitnessMacro", id: rawValue)
    }

    var severity: DiagnosticSeverity { .error }
}
