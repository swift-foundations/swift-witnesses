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
    // Future: static let spy = DeriveOptions(rawValue: 1 << 2)
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
    // Future: case "spy": return .spy
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

        // Determine access level
        let isPublic = structDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }

        // Generate public initializer if needed
        if isPublic {
            members.append(generatePublicInit(for: closureProperties, structDecl: structDecl))
        }

        // Generate methods for labeled closures
        for property in closureProperties where property.hasLabels {
            if let method = generateMethod(for: property) {
                members.append(method)
            }
        }

        // Generate Action enum
        members.append(generateActionEnum(for: closureProperties))

        // Generate Observe accessor struct and property
        members.append(generateObserveStruct(for: closureProperties, structName: structDecl.name.text))
        members.append(generateObserveProperty())

        // Generate callAsFunction if .generator is specified and there's exactly one closure
        let deriveOptions = parseDeriveOptions(from: node)
        if deriveOptions.contains(.generator), closureProperties.count == 1 {
            let property = closureProperties[0]
            members.append(generateCallAsFunction(for: property))
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
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation,
              let functionType = extractFunctionType(from: typeAnnotation.type) else {
            return []
        }

        // Only deprecate if the closure has labeled parameters
        let hasLabels = functionType.parameters.contains { param in
            param.secondName != nil
        }

        guard hasLabels else { return [] }

        let methodSignature = generateMethodSignature(
            name: identifier.identifier.text,
            functionType: functionType
        )

        // Use string parsing for simpler attribute construction
        let attributeString = "@available(*, deprecated, message: \"Use '\(methodSignature)' instead\")"
        let attribute = AttributeSyntax(stringLiteral: attributeString)
        return [attribute]
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

        // All @Witness types conform to __WitnessProtocol
        let witnessExt = try ExtensionDeclSyntax("extension \(type.trimmed): Witness_Primitives.__WitnessProtocol {}")
        extensions.append(witnessExt)

        // Enums also conform to Optic.Prism.Accessible for composition support
        // Uses hoisted __OpticPrismAccessible since Optic.Prism.Accessible is a typealias
        if declaration.is(EnumDeclSyntax.self) {
            let prismExt = try ExtensionDeclSyntax("extension \(type.trimmed): Optic_Primitives.__OpticPrismAccessible {}")
            extensions.append(prismExt)
        }

        // For structs, generate the unimplemented() and optionally mock() extensions
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            let closureProperties = extractClosureProperties(from: structDecl)
            if !closureProperties.isEmpty {
                let unimplementedExt = try generateUnimplementedExtension(
                    for: structDecl,
                    type: type,
                    closureProperties: closureProperties
                )
                extensions.append(unimplementedExt)

                // Generate mock() if .mock is specified
                let deriveOptions = parseDeriveOptions(from: node)
                if deriveOptions.contains(.mock) {
                    let mockExt = try generateMockExtension(
                        for: structDecl,
                        type: type,
                        closureProperties: closureProperties
                    )
                    extensions.append(mockExt)
                }

                // Generate constant() if .generator is specified and there's exactly one closure
                if deriveOptions.contains(.generator), closureProperties.count == 1 {
                    let constantExt = try generateConstantExtension(
                        for: structDecl,
                        type: type,
                        property: closureProperties[0]
                    )
                    extensions.append(constantExt)
                }
            }
        }

        return extensions
    }

    private static func generateUnimplementedExtension(
        for structDecl: StructDeclSyntax,
        type: some TypeSyntaxProtocol,
        closureProperties: [ClosureProperty]
    ) throws -> ExtensionDeclSyntax {
        let structName = structDecl.name.text
        let isPublic = structDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
        let accessModifier = isPublic ? "public " : ""

        // Generate closure initializers that throw Witness.Unimplemented.Error
        let closureInits = closureProperties.map { property in
            generateUnimplementedClosure(for: property, structName: structName)
        }.joined(separator: ",\n            ")

        return try ExtensionDeclSyntax(
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
    }

    private static func generateMockExtension(
        for structDecl: StructDeclSyntax,
        type: some TypeSyntaxProtocol,
        closureProperties: [ClosureProperty]
    ) throws -> ExtensionDeclSyntax {
        let structName = structDecl.name.text
        let isPublic = structDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
        let accessModifier = isPublic ? "public " : ""

        // Generate parameters for mock() - takes VALUES, not closures
        // Void returns get default value of (), non-Void are required
        let mockParameters = closureProperties.map { property in
            generateMockParameter(for: property)
        }.joined(separator: ",\n            ")

        // Generate closure initializers that return the mock values
        let closureInits = closureProperties.map { property in
            generateMockClosure(for: property)
        }.joined(separator: ",\n                ")

        return try ExtensionDeclSyntax(
            """
            extension \(type.trimmed) {
                /// Creates a mock witness with fixed return values.
                ///
                /// This is useful for tests where you want simple, predictable values:
                /// ```swift
                /// let api = \(raw: structName).mock(fetchUser: testUser)
                /// ```
                ///
                /// For Void-returning operations, the parameter defaults to `()`.
                @inlinable
                \(raw: accessModifier)static func mock(
                    \(raw: mockParameters)
                ) -> Self {
                    Self(
                        \(raw: closureInits)
                    )
                }
            }
            """
        )
    }

    // MARK: - Generator Extension

    private static func generateConstantExtension(
        for structDecl: StructDeclSyntax,
        type: some TypeSyntaxProtocol,
        property: ClosureProperty
    ) throws -> ExtensionDeclSyntax {
        let isPublic = structDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
        let accessModifier = isPublic ? "public " : ""

        let returnType = property.returnType.trimmedDescription

        // Include typed throws annotation if present (for proper type inference)
        let throwsAnnotation: String
        if let throwsType = property.throwsType {
            throwsAnnotation = "throws(\(throwsType.trimmedDescription)) "
        } else if property.isThrowing {
            throwsAnnotation = "throws "
        } else {
            throwsAnnotation = ""
        }

        // Generate closure with appropriate parameter handling
        let closureBody: String
        if property.parameters.isEmpty {
            closureBody = "{ () \(throwsAnnotation)-> \(returnType) in value }"
        } else {
            let underscoreParams = property.parameters.map { _ in "_" }.joined(separator: ", ")
            closureBody = "{ (\(underscoreParams)) \(throwsAnnotation)-> \(returnType) in value }"
        }

        return try ExtensionDeclSyntax(
            """
            extension \(type.trimmed) {
                /// Creates a generator that always returns the given value.
                ///
                /// ```swift
                /// let generator = \(raw: structDecl.name.text).constant(fixedValue)
                /// print(generator())  // fixedValue
                /// print(generator())  // fixedValue
                /// ```
                @inlinable
                \(raw: accessModifier)static func constant(_ value: \(raw: returnType)) -> Self {
                    Self(\(raw: property.name): \(raw: closureBody))
                }
            }
            """
        )
    }
}

// MARK: - Mock Generation Helpers

/// Generates a mock() parameter for a closure property.
/// - Void return types get a default value of `()`
/// - Non-Void return types are required parameters
private func generateMockParameter(for property: ClosureProperty) -> String {
    let returnType = property.returnType.trimmedDescription
    let isVoid = returnType == "Void" || returnType == "()"

    if isVoid {
        return "\(property.name): Void = ()"
    } else {
        return "\(property.name): \(returnType)"
    }
}

/// Generates a mock closure initializer that returns the mock value.
private func generateMockClosure(for property: ClosureProperty) -> String {
    let returnType = property.returnType.trimmedDescription
    let isVoid = returnType == "Void" || returnType == "()"

    // Include typed throws annotation if present (needed for proper type inference)
    let throwsAnnotation: String
    if let throwsType = property.throwsType {
        throwsAnnotation = "throws(\(throwsType.trimmedDescription)) "
    } else if property.isThrowing {
        throwsAnnotation = "throws "
    } else {
        throwsAnnotation = ""
    }

    // Generate closure with appropriate parameter handling
    // Syntax: { (params) throws(E) -> T in body }
    if property.parameters.isEmpty {
        // No parameters: { () throws(E) -> T in value }
        if isVoid {
            return "\(property.name): { () \(throwsAnnotation)-> \(returnType) in }"
        } else {
            return "\(property.name): { () \(throwsAnnotation)-> \(returnType) in \(property.name) }"
        }
    } else {
        // Has parameters: { (_, _) throws(E) -> T in value }
        let underscoreParams = property.parameters.map { _ in "_" }.joined(separator: ", ")
        if isVoid {
            return "\(property.name): { (\(underscoreParams)) \(throwsAnnotation)-> \(returnType) in }"
        } else {
            return "\(property.name): { (\(underscoreParams)) \(throwsAnnotation)-> \(returnType) in \(property.name) }"
        }
    }
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
}

struct ClosureParameter {
    let label: String?
    let internalName: String
    let type: TypeSyntax
    let isInout: Bool
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
    var parameters: [ClosureParameter] = []

    for (index, param) in functionType.parameters.enumerated() {
        let label = param.secondName?.text
        let internalName = label ?? "p\(index)"
        let isInout = param.type.is(AttributedTypeSyntax.self) &&
            param.type.as(AttributedTypeSyntax.self)?.specifiers.contains(where: {
                $0.as(SimpleTypeSpecifierSyntax.self)?.specifier.tokenKind == .keyword(.inout)
            }) == true

        parameters.append(ClosureParameter(
            label: label,
            internalName: internalName,
            type: param.type,
            isInout: isInout
        ))
    }

    return parameters
}

// MARK: - Public Init Generation

private func generatePublicInit(for properties: [ClosureProperty], structDecl: StructDeclSyntax) -> DeclSyntax {
    // Extract full type syntax from the struct's member declarations
    var fullTypes: [String: String] = [:]
    for member in structDecl.memberBlock.members {
        if let varDecl = member.decl.as(VariableDeclSyntax.self),
           let binding = varDecl.bindings.first,
           let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
           let typeAnnotation = binding.typeAnnotation {
            fullTypes[identifier.identifier.text] = typeAnnotation.type.trimmedDescription
        }
    }

    let parameters = properties.map { property in
        let fullType = fullTypes[property.name] ?? "\(property.functionType)"
        return "\(property.name): @escaping \(fullType)"
    }.joined(separator: ",\n        ")

    let assignments = properties.map { property in
        "self.\(property.name) = \(property.name)"
    }.joined(separator: "\n        ")

    return """
        public init(
            \(raw: parameters)
        ) {
            \(raw: assignments)
        }
        """
}

// MARK: - Method Generation

private func generateMethod(for property: ClosureProperty) -> DeclSyntax? {
    guard property.hasLabels else { return nil }

    let parameters = property.parameters.enumerated().map { index, param in
        let label = param.label ?? "_"
        let internalName = "p\(index)"
        return "\(label) \(internalName): \(param.type)"
    }.joined(separator: ", ")

    let effectSpecifiers: String = {
        var specs: [String] = []
        if property.isAsync { specs.append("async") }
        if property.isThrowing { specs.append("throws") }
        return specs.isEmpty ? "" : " " + specs.joined(separator: " ")
    }()

    let returnClause = property.returnType.trimmedDescription == "Void"
        ? ""
        : " -> \(property.returnType)"

    let callArguments = property.parameters.enumerated().map { index, param in
        let prefix = param.isInout ? "&" : ""
        return "\(prefix)p\(index)"
    }.joined(separator: ", ")

    let awaitKeyword = property.isAsync ? "await " : ""
    let tryKeyword = property.isThrowing ? "try " : ""

    return """
        @inlinable
        public func \(raw: property.name)(\(raw: parameters))\(raw: effectSpecifiers)\(raw: returnClause) {
            \(raw: tryKeyword)\(raw: awaitKeyword)self.\(raw: property.name)(\(raw: callArguments))
        }
        """
}

/// Generates callAsFunction() for .generator derive mode.
private func generateCallAsFunction(for property: ClosureProperty) -> DeclSyntax {
    let effectSpecifiers: String = {
        var specs: [String] = []
        if property.isAsync { specs.append("async") }
        if property.isThrowing { specs.append("throws") }
        return specs.isEmpty ? "" : " " + specs.joined(separator: " ")
    }()

    let returnClause = property.returnType.trimmedDescription == "Void"
        ? ""
        : " -> \(property.returnType)"

    let awaitKeyword = property.isAsync ? "await " : ""
    let tryKeyword = property.isThrowing ? "try " : ""

    // Generate parameter list if the closure has parameters
    let parameters = property.parameters.enumerated().map { index, param in
        let label = param.label ?? "_"
        let internalName = "p\(index)"
        return "\(label) \(internalName): \(param.type)"
    }.joined(separator: ", ")

    let callArguments = property.parameters.enumerated().map { index, param in
        let prefix = param.isInout ? "&" : ""
        return "\(prefix)p\(index)"
    }.joined(separator: ", ")

    return """
        @inlinable
        public func callAsFunction(\(raw: parameters))\(raw: effectSpecifiers)\(raw: returnClause) {
            \(raw: tryKeyword)\(raw: awaitKeyword)self.\(raw: property.name)(\(raw: callArguments))
        }
        """
}

private func generateMethodSignature(name: String, functionType: FunctionTypeSyntax) -> String {
    let labels = functionType.parameters.enumerated().map { index, param in
        param.secondName?.text ?? "_"
    }

    if labels.isEmpty {
        return "\(name)()"
    }

    let labelString = labels.map { "\($0):" }.joined()
    return "\(name)(\(labelString))"
}

// MARK: - Action Enum Generation

private func generateActionEnum(for properties: [ClosureProperty]) -> DeclSyntax {
    let caseCount = properties.count

    // Generate Action cases (inputs only)
    let actionCases = properties.map { property in
        if property.parameters.isEmpty {
            return "case \(property.name)"
        }

        let associatedValues = property.parameters.enumerated().map { index, param in
            if let label = param.label {
                return "\(label): \(param.type)"
            } else {
                return "\(param.type)"
            }
        }.joined(separator: ", ")

        return "case \(property.name)(\(associatedValues))"
    }.joined(separator: "\n            ")

    // Generate Case enum cases (no associated values)
    let caseCases = properties.map { "case \($0.name)" }.joined(separator: "\n                ")

    // Generate Case.ordinal switch
    let caseOrdinalCases = properties.enumerated().map { index, property in
        "case .\(property.name): Ordinal_Primitives.Ordinal(\(index))"
    }.joined(separator: "\n                    ")

    // Generate Case.init(__unchecked:ordinal:) switch - last case is default
    let caseInitCases: String
    if properties.count == 1 {
        caseInitCases = "default: self = .\(properties[0].name)"
    } else {
        let explicitCases = properties.dropLast().enumerated().map { index, property in
            "case \(index): self = .\(property.name)"
        }.joined(separator: "\n                    ")
        let defaultCase = "default: self = .\(properties.last!.name)"
        caseInitCases = explicitCases + "\n                    " + defaultCase
    }

    // Generate Action.case property switch
    let actionCaseCases = properties.map { property in
        "case .\(property.name): .\(property.name)"
    }.joined(separator: "\n                ")

    // Generate Prisms struct properties
    let prismProperties = generatePrismProperties(for: properties)

    // Generate Action.Result cases with typed Result for each action
    let resultCases = properties.map { property in
        generateTypedResultCase(for: property)
    }.joined(separator: "\n                ")

    // Structure:
    // - Action enum has cases for each closure (inputs only)
    // - Action.Case is the enumerable discriminant (no associated values)
    // - Action.Result is a typed enum with Result<Success, Failure> per action
    // - Action.Outcome pairs an action with its typed result
    // - Action.Prisms provides prisms for each case
    return """
        public enum Action: Sendable {
            \(raw: actionCases)

            /// The enumerable case discriminant (without associated values).
            public enum Case: Finite_Primitives.Finite.Enumerable, Sendable {
                \(raw: caseCases)

                @inlinable
                public static var count: Cardinal_Primitives.Cardinal { Cardinal_Primitives.Cardinal(\(raw: caseCount)) }

                @inlinable
                public var ordinal: Ordinal_Primitives.Ordinal {
                    switch self {
                    \(raw: caseOrdinalCases)
                    }
                }

                @inlinable
                public init(__unchecked: Void, ordinal: Ordinal_Primitives.Ordinal) {
                    switch ordinal.rawValue {
                    \(raw: caseInitCases)
                    }
                }
            }

            /// This action's case discriminant.
            @inlinable
            public var `case`: Case {
                switch self {
                \(raw: actionCaseCases)
                }
            }

            /// Typed result for each action, preserving the specific success and error types.
            public enum Result: Sendable {
                \(raw: resultCases)
            }

            /// An action paired with its typed result.
            public struct Outcome: Sendable {
                public let action: Action
                public let result: Result

                @inlinable
                public init(action: Action, result: Result) {
                    self.action = action
                    self.result = result
                }
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
            ///
            /// - Parameter keyPath: A key path to a prism in `Prisms`.
            /// - Returns: `true` if this action matches the prism's case.
            @inlinable
            public func `is`<Value>(_ keyPath: KeyPath<Prisms, Optic_Primitives.Optic.Prism<Action, Value>>) -> Bool {
                Self.prisms[keyPath: keyPath].extract(self) != nil
            }

            /// Extracts the associated value for the given prism, if this action matches.
            ///
            /// - Parameter keyPath: A key path to a prism in `Prisms`.
            /// - Returns: The extracted value, or `nil` if this action doesn't match.
            @inlinable
            public subscript<Value>(prism keyPath: KeyPath<Prisms, Optic_Primitives.Optic.Prism<Action, Value>>) -> Value? {
                Self.prisms[keyPath: keyPath].extract(self)
            }
        }
        """
}

/// Generates a typed Result case for a closure property.
/// e.g., `case fetchUser(Swift.Result<String, Witness.Unimplemented.Error>)`
private func generateTypedResultCase(for property: ClosureProperty) -> String {
    let returnType = property.returnType.trimmedDescription
    let errorType = property.throwsType?.trimmedDescription ?? "Never"
    return "case \(property.name)(Swift.Result<\(returnType), \(errorType)>)"
}

/// Generates prism properties for each closure property.
private func generatePrismProperties(for properties: [ClosureProperty]) -> String {
    properties.map { property in
        generatePrismProperty(for: property)
    }.joined(separator: "\n\n                ")
}

/// Generates a single prism property for a closure property.
private func generatePrismProperty(for property: ClosureProperty) -> String {
    if property.parameters.isEmpty {
        // Case with no associated values - prism to Void
        return """
        public var \(property.name): Optic_Primitives.Optic.Prism<Action, Void> {
                    Optic_Primitives.Optic.Prism(
                        embed: { _ in .\(property.name) },
                        extract: { if case .\(property.name) = $0 { return () } else { return nil } }
                    )
                }
        """
    } else if property.parameters.count == 1 {
        // Single parameter - prism directly to that type
        let param = property.parameters[0]
        let paramType = param.type.trimmedDescription
        let embedArg = param.label != nil ? "\(param.label!): $0" : "$0"
        let extractPattern = param.label != nil ? "\(param.label!): let v" : "let v"

        return """
        public var \(property.name): Optic_Primitives.Optic.Prism<Action, \(paramType)> {
                    Optic_Primitives.Optic.Prism(
                        embed: { .\(property.name)(\(embedArg)) },
                        extract: { if case .\(property.name)(\(extractPattern)) = $0 { return v } else { return nil } }
                    )
                }
        """
    } else {
        // Multiple parameters - prism to a labeled tuple
        let tupleTypes = property.parameters.map { param in
            if let label = param.label {
                return "\(label): \(param.type.trimmedDescription)"
            } else {
                return param.type.trimmedDescription
            }
        }.joined(separator: ", ")

        let embedArgs = property.parameters.enumerated().map { index, param in
            if let label = param.label {
                return "\(label): $0.\(index)"
            } else {
                return "$0.\(index)"
            }
        }.joined(separator: ", ")

        let extractPatterns = property.parameters.enumerated().map { index, param in
            if let label = param.label {
                return "\(label): let v\(index)"
            } else {
                return "let v\(index)"
            }
        }.joined(separator: ", ")

        let extractTuple = property.parameters.enumerated().map { index, param in
            if let label = param.label {
                return "\(label): v\(index)"
            } else {
                return "v\(index)"
            }
        }.joined(separator: ", ")

        return """
        public var \(property.name): Optic_Primitives.Optic.Prism<Action, (\(tupleTypes))> {
                    Optic_Primitives.Optic.Prism(
                        embed: { .\(property.name)(\(embedArgs)) },
                        extract: { if case .\(property.name)(\(extractPatterns)) = $0 { return (\(extractTuple)) } else { return nil } }
                    )
                }
        """
    }
}

// MARK: - Unimplemented Closure Generation

private func generateUnimplementedClosure(for property: ClosureProperty, structName: String) -> String {
    // Build operation signature string for error message
    let operationSignature = buildOperationSignature(for: property)

    // Include typed throws annotation if present
    let throwsAnnotation: String
    if let throwsType = property.throwsType {
        throwsAnnotation = "throws(\(throwsType.trimmedDescription)) "
    } else if property.isThrowing {
        throwsAnnotation = "throws "
    } else {
        throwsAnnotation = ""
    }

    let returnType = property.returnType.trimmedDescription

    // Generate closure with explicit typed throws annotation
    // Syntax: { (params) throws(E) -> T in body }
    let closureStart: String
    if property.parameters.isEmpty {
        closureStart = "{ () \(throwsAnnotation)-> \(returnType) in"
    } else {
        let underscoreParams = property.parameters.map { _ in "_" }.joined(separator: ", ")
        closureStart = "{ (\(underscoreParams)) \(throwsAnnotation)-> \(returnType) in"
    }

    // All unimplemented closures throw the error
    return """
\(property.name): \(closureStart)
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

// MARK: - Observe Accessor Generation

private func generateObserveStruct(for properties: [ClosureProperty], structName: String) -> DeclSyntax {
    // Generate callAsFunction closures (both - before and after with two closures)
    let bothClosures = properties.map { property -> String in
        generateBothObserveClosure(for: property, structName: structName)
    }.joined(separator: ",\n                    ")

    // Generate before closures
    let beforeClosures = properties.map { property -> String in
        generateBeforeObserveClosure(for: property, structName: structName)
    }.joined(separator: ",\n                    ")

    // Generate after closures
    let afterClosures = properties.map { property -> String in
        generateAfterObserveClosure(for: property, structName: structName)
    }.joined(separator: ",\n                    ")

    return """
        public struct Observe: Sendable {
            @usableFromInline
            internal let witness: \(raw: structName)

            @usableFromInline
            internal init(_ witness: \(raw: structName)) {
                self.witness = witness
            }

            @inlinable
            public func callAsFunction(
                _ before: @escaping @Sendable (Action) -> Void,
                after: @escaping @Sendable (Action.Outcome) -> Void
            ) -> \(raw: structName) {
                \(raw: structName)(
                    \(raw: bothClosures)
                )
            }

            @inlinable
            public func before(
                _ observer: @escaping @Sendable (Action) -> Void
            ) -> \(raw: structName) {
                \(raw: structName)(
                    \(raw: beforeClosures)
                )
            }

            @inlinable
            public func after(
                _ observer: @escaping @Sendable (Action.Outcome) -> Void
            ) -> \(raw: structName) {
                \(raw: structName)(
                    \(raw: afterClosures)
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

private func generateBothObserveClosure(for property: ClosureProperty, structName: String) -> String {
    let captureList = "[witness]"
    let parameterNames = property.parameters.enumerated().map { index, param in
        param.label ?? "p\(index)"
    }
    let callArgs = parameterNames.joined(separator: ", ")
    let actionConstruction = formatActionConstruction(for: property)

    let awaitKeyword = property.isAsync ? "await " : ""

    let returnType = property.returnType.trimmedDescription
    let hasReturn = returnType != "Void" && returnType != "()"
    let resultValue = hasReturn ? "result" : "()"

    // Include typed throws annotation if present
    let throwsAnnotation: String
    if let throwsType = property.throwsType {
        throwsAnnotation = "throws(\(throwsType.trimmedDescription)) "
    } else if property.isThrowing {
        throwsAnnotation = "throws "
    } else {
        throwsAnnotation = ""
    }

    // Use typed Action.Result case for this property
    let successResult = "Action.Outcome(action: action, result: .\(property.name)(.success(\(resultValue))))"
    // For typed throws, cast the error to the specific type (safe since closure is typed)
    let errorCast = property.throwsType != nil ? "error as! \(property.throwsType!.trimmedDescription)" : "error"
    let failureResult = "Action.Outcome(action: action, result: .\(property.name)(.failure(\(errorCast))))"

    // Closure params with proper syntax: { [capture] (params) throws(E) -> T in body }
    let closureParamsWithParens = parameterNames.isEmpty ? "()" : "(\(parameterNames.joined(separator: ", ")))"

    // For typed throws, also cast when rethrowing
    let throwError = property.throwsType != nil ? "throw \(errorCast)" : "throw error"

    if property.isThrowing {
        return """
        \(property.name): { \(captureList) \(closureParamsWithParens) \(throwsAnnotation)-> \(returnType) in
                        let action: Action = \(actionConstruction)
                        before(action)
                        do {
                            \(hasReturn ? "let result = " : "")try \(awaitKeyword)witness.\(property.name)(\(callArgs))
                            after(\(successResult))
                            \(hasReturn ? "return result" : "")
                        } catch {
                            after(\(failureResult))
                            \(throwError)
                        }
                    }
        """
    } else {
        return """
        \(property.name): { \(captureList) \(closureParamsWithParens) -> \(returnType) in
                        let action: Action = \(actionConstruction)
                        before(action)
                        \(hasReturn ? "let result = " : "")\(awaitKeyword)witness.\(property.name)(\(callArgs))
                        after(\(successResult))
                        \(hasReturn ? "return result" : "")
                    }
        """
    }
}

private func generateBeforeObserveClosure(for property: ClosureProperty, structName: String) -> String {
    let captureList = "[witness]"
    let parameterNames = property.parameters.enumerated().map { index, param in
        param.label ?? "p\(index)"
    }
    let callArgs = parameterNames.joined(separator: ", ")
    let actionConstruction = formatActionConstruction(for: property)

    let awaitKeyword = property.isAsync ? "await " : ""
    let tryKeyword = property.isThrowing ? "try " : ""

    let returnType = property.returnType.trimmedDescription
    let hasReturn = returnType != "Void" && returnType != "()"
    let returnKeyword = hasReturn ? "return " : ""

    // Include typed throws annotation if present
    let throwsAnnotation: String
    if let throwsType = property.throwsType {
        throwsAnnotation = "throws(\(throwsType.trimmedDescription)) "
    } else if property.isThrowing {
        throwsAnnotation = "throws "
    } else {
        throwsAnnotation = ""
    }

    // Closure params with proper syntax: { [capture] (params) throws(E) -> T in body }
    let closureParamsWithParens = parameterNames.isEmpty ? "()" : "(\(parameterNames.joined(separator: ", ")))"

    return """
    \(property.name): { \(captureList) \(closureParamsWithParens) \(throwsAnnotation)-> \(returnType) in
                    observer(\(actionConstruction))
                    \(returnKeyword)\(tryKeyword)\(awaitKeyword)witness.\(property.name)(\(callArgs))
                }
    """
}

private func generateAfterObserveClosure(for property: ClosureProperty, structName: String) -> String {
    let captureList = "[witness]"
    let parameterNames = property.parameters.enumerated().map { index, param in
        param.label ?? "p\(index)"
    }
    let callArgs = parameterNames.joined(separator: ", ")
    let actionConstruction = formatActionConstruction(for: property)

    let awaitKeyword = property.isAsync ? "await " : ""

    let returnType = property.returnType.trimmedDescription
    let hasReturn = returnType != "Void" && returnType != "()"
    let resultValue = hasReturn ? "result" : "()"

    // Include typed throws annotation if present
    let throwsAnnotation: String
    if let throwsType = property.throwsType {
        throwsAnnotation = "throws(\(throwsType.trimmedDescription)) "
    } else if property.isThrowing {
        throwsAnnotation = "throws "
    } else {
        throwsAnnotation = ""
    }

    // Use typed Action.Result case for this property
    let successResult = "Action.Outcome(action: action, result: .\(property.name)(.success(\(resultValue))))"
    // For typed throws, cast the error to the specific type (safe since closure is typed)
    let errorCast = property.throwsType != nil ? "error as! \(property.throwsType!.trimmedDescription)" : "error"
    let failureResult = "Action.Outcome(action: action, result: .\(property.name)(.failure(\(errorCast))))"

    // Closure params with proper syntax: { [capture] (params) throws(E) -> T in body }
    let closureParamsWithParens = parameterNames.isEmpty ? "()" : "(\(parameterNames.joined(separator: ", ")))"

    // For typed throws, also cast when rethrowing
    let throwError = property.throwsType != nil ? "throw \(errorCast)" : "throw error"

    if property.isThrowing {
        return """
        \(property.name): { \(captureList) \(closureParamsWithParens) \(throwsAnnotation)-> \(returnType) in
                        let action: Action = \(actionConstruction)
                        do {
                            \(hasReturn ? "let result = " : "")try \(awaitKeyword)witness.\(property.name)(\(callArgs))
                            observer(\(successResult))
                            \(hasReturn ? "return result" : "")
                        } catch {
                            observer(\(failureResult))
                            \(throwError)
                        }
                    }
        """
    } else {
        return """
        \(property.name): { \(captureList) \(closureParamsWithParens) -> \(returnType) in
                        let action: Action = \(actionConstruction)
                        \(hasReturn ? "let result = " : "")\(awaitKeyword)witness.\(property.name)(\(callArgs))
                        observer(\(successResult))
                        \(hasReturn ? "return result" : "")
                    }
        """
    }
}

/// Formats action construction: `.propertyName` or `.propertyName(label: value, ...)`
private func formatActionConstruction(for property: ClosureProperty) -> String {
    if property.parameters.isEmpty {
        return ".\(property.name)"
    }
    let args = property.parameters.enumerated().map { index, param in
        let name = param.label ?? "p\(index)"
        if let label = param.label {
            return "\(label): \(name)"
        } else {
            return name
        }
    }.joined(separator: ", ")
    return ".\(property.name)(\(args))"
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
