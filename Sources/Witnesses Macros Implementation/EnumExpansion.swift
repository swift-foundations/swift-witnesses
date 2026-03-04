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

// MARK: - Enum Case Extraction

struct EnumCase: Sendable {
    let name: String
    let parameters: [EnumCaseParameter]

    init(name: String, parameters: [EnumCaseParameter]) {
        self.name = name
        self.parameters = parameters
    }
}

struct EnumCaseParameter: Sendable {
    let label: String?
    let type: String

    init(label: String?, type: String) {
        self.label = label
        self.type = type
    }
}

func extractEnumCases(from enumDecl: EnumDeclSyntax) -> [EnumCase] {
    var cases: [EnumCase] = []

    for member in enumDecl.memberBlock.members {
        guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else {
            continue
        }

        for element in caseDecl.elements {
            let name = element.name.text
            var parameters: [EnumCaseParameter] = []

            if let parameterClause = element.parameterClause {
                for param in parameterClause.parameters {
                    let label = param.firstName?.text
                    parameters.append(EnumCaseParameter(
                        label: label,
                        type: param.type.trimmedDescription
                    ))
                }
            }

            cases.append(EnumCase(name: name, parameters: parameters))
        }
    }

    return cases
}

// MARK: - Enum Prism Generation

func generateEnumPrismMembers(for cases: [EnumCase], enumName: String) -> [DeclSyntax] {
    var members: [DeclSyntax] = []

    // Generate direct computed properties for each case (zero-overhead extraction)
    for enumCase in cases {
        members.append(generateEnumComputedProperty(for: enumCase))
    }

    // Generate Case discriminant enum (for iteration support)
    let caseCount = cases.count
    let escapedCaseNames = cases.map { escapeIdentifier($0.name) }
    let caseCases = escapedCaseNames.map { "case \($0)" }.joined(separator: "\n            ")
    let caseOrdinalCases = cases.enumerated().map { index, c in
        "case .\(escapeIdentifier(c.name)): Ordinal_Primitives.Ordinal(\(index))"
    }.joined(separator: "\n                ")
    let uncheckedInitCases = cases.enumerated().map { index, c in
        if index == cases.count - 1 {
            "default: self = .\(escapeIdentifier(c.name))"
        } else {
            "case \(index): self = .\(escapeIdentifier(c.name))"
        }
    }.joined(separator: "\n                ")
    let selfCaseCases = cases.map { c in
        let escaped = escapeIdentifier(c.name)
        return "case .\(escaped): .\(escaped)"
    }.joined(separator: "\n            ")

    let caseEnum: DeclSyntax = """
        /// The enumerable case discriminant (without associated values).
        ///
        /// Use this for iteration over all case kinds:
        /// ```swift
        /// for c in \(raw: enumName).Case.allCases {
        ///     print(c)
        /// }
        /// ```
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
                \(raw: uncheckedInitCases)
                }
            }
        }
        """
    members.append(caseEnum)

    // Generate `case` property
    let caseProperty: DeclSyntax = """
        /// This value's case discriminant.
        @inlinable
        public var `case`: Case {
            switch self {
            \(raw: selfCaseCases)
            }
        }
        """
    members.append(caseProperty)

    // Generate Prisms struct
    let prismProperties = cases.map { enumCase in
        generateEnumPrismProperty(for: enumCase, enumName: enumName)
    }.joined(separator: "\n\n        ")

    let prismsStruct: DeclSyntax = """
        /// Prisms for each enum case, enabling type-safe case matching and extraction.
        public struct Prisms: Sendable {
            @inlinable
            public init() {}

            \(raw: prismProperties)
        }
        """
    members.append(prismsStruct)

    // Generate prisms static property
    let prismsProperty: DeclSyntax = """
        /// Access prisms for each enum case.
        @inlinable
        public static var prisms: Prisms { Prisms() }
        """
    members.append(prismsProperty)

    // Generate is(_:) method
    let isMethod: DeclSyntax = """
        /// Checks if this value matches the given prism.
        ///
        /// - Parameter keyPath: A key path to a prism in `Prisms`.
        /// - Returns: `true` if this value matches the prism's case.
        @inlinable
        public func `is`<Value>(_ keyPath: KeyPath<Prisms, Optic_Primitives.Optic.Prism<\(raw: enumName), Value>>) -> Bool {
            Self.prisms[keyPath: keyPath].extract(self) != nil
        }
        """
    members.append(isMethod)

    // Generate subscript[prism:]
    let prismSubscript: DeclSyntax = """
        /// Extracts the associated value for the given prism, if this value matches.
        ///
        /// - Parameter keyPath: A key path to a prism in `Prisms`.
        /// - Returns: The extracted value, or `nil` if this value doesn't match.
        @inlinable
        public subscript<Value>(prism keyPath: KeyPath<Prisms, Optic_Primitives.Optic.Prism<\(raw: enumName), Value>>) -> Value? {
            Self.prisms[keyPath: keyPath].extract(self)
        }
        """
    members.append(prismSubscript)

    // Generate mutating modify method
    let modifyMethod: DeclSyntax = """
        /// Modifies the associated value in place if this value matches the given prism.
        ///
        /// - Parameters:
        ///   - keyPath: A key path to a prism in `Prisms`.
        ///   - transform: A closure that modifies the extracted value.
        @inlinable
        public mutating func modify<Value>(_ keyPath: KeyPath<Prisms, Optic_Primitives.Optic.Prism<\(raw: enumName), Value>>, _ transform: (inout Value) -> Void) {
            let prism = Self.prisms[keyPath: keyPath]
            guard var value = prism.extract(self) else { return }
            transform(&value)
            self = prism.embed(value)
        }
        """
    members.append(modifyMethod)

    return members
}

/// Generates a direct computed property for extracting an enum case's associated value.
private func generateEnumComputedProperty(for enumCase: EnumCase) -> DeclSyntax {
    if enumCase.parameters.isEmpty {
        return """
            /// Extracts `Void` if this is the `\(raw: enumCase.name)` case, otherwise `nil`.
            @inlinable
            public var \(raw: enumCase.name): Void? {
                if case .\(raw: enumCase.name) = self { () } else { nil }
            }
            """
    } else if enumCase.parameters.count == 1 {
        let param = enumCase.parameters[0]
        let paramType = param.type
        let extractPattern = param.label.map { "\($0): let v" } ?? "let v"

        return """
            /// Extracts the associated value if this is the `\(raw: enumCase.name)` case, otherwise `nil`.
            @inlinable
            public var \(raw: enumCase.name): \(raw: paramType)? {
                if case .\(raw: enumCase.name)(\(raw: extractPattern)) = self { v } else { nil }
            }
            """
    } else {
        let tupleTypes = enumCase.parameters.map { param in
            if let label = param.label {
                let escaped = escapeIdentifier(label)
                return "\(escaped): \(param.type)"
            } else {
                return param.type
            }
        }.joined(separator: ", ")

        let extractPatterns = enumCase.parameters.enumerated().map { index, param in
            if let label = param.label {
                return "\(label): let v\(index)"
            } else {
                return "let v\(index)"
            }
        }.joined(separator: ", ")

        let extractTuple = enumCase.parameters.enumerated().map { index, param in
            if let label = param.label {
                let escaped = escapeIdentifier(label)
                return "\(escaped): v\(index)"
            } else {
                return "v\(index)"
            }
        }.joined(separator: ", ")

        return """
            /// Extracts the associated values if this is the `\(raw: enumCase.name)` case, otherwise `nil`.
            @inlinable
            public var \(raw: enumCase.name): (\(raw: tupleTypes))? {
                if case .\(raw: enumCase.name)(\(raw: extractPatterns)) = self { (\(raw: extractTuple)) } else { nil }
            }
            """
    }
}

private func generateEnumPrismProperty(for enumCase: EnumCase, enumName: String) -> String {
    let prismCase = PrismCase(
        caseName: escapeIdentifier(enumCase.name),
        rootTypeName: enumName,
        parameters: enumCase.parameters.map { (
            $0.label.map { escapeIdentifier($0) },
            $0.type
        )}
    )
    return generatePrism(for: prismCase)
}

// MARK: - Shared Prism Generation

/// Common representation for a prism case, used by both Action (struct) and enum prism generation.
struct PrismCase {
    let caseName: String
    let rootTypeName: String
    let parameters: [(label: String?, type: String)]
}

/// Generates a single prism property for a case.
func generatePrism(for prismCase: PrismCase) -> String {
    let name = prismCase.caseName
    let root = prismCase.rootTypeName

    if prismCase.parameters.isEmpty {
        return """
        public var \(name): Optic_Primitives.Optic.Prism<\(root), Void> {
                    Optic_Primitives.Optic.Prism(
                        embed: { _ in .\(name) },
                        extract: { if case .\(name) = $0 { return () } else { return nil } }
                    )
                }
        """
    } else if prismCase.parameters.count == 1 {
        let param = prismCase.parameters[0]
        let paramType = param.type
        let embedArg = param.label != nil ? "\(param.label!): $0" : "$0"
        let extractPattern = param.label != nil ? "\(param.label!): let v" : "let v"

        return """
        public var \(name): Optic_Primitives.Optic.Prism<\(root), \(paramType)> {
                    Optic_Primitives.Optic.Prism(
                        embed: { .\(name)(\(embedArg)) },
                        extract: { if case .\(name)(\(extractPattern)) = $0 { return v } else { return nil } }
                    )
                }
        """
    } else {
        let tupleTypes = prismCase.parameters.map { p in
            p.label != nil ? "\(p.label!): \(p.type)" : p.type
        }.joined(separator: ", ")

        let embedArgs = prismCase.parameters.enumerated().map { i, p in
            p.label != nil ? "\(p.label!): $0.\(i)" : "$0.\(i)"
        }.joined(separator: ", ")

        let extractPatterns = prismCase.parameters.enumerated().map { i, p in
            p.label != nil ? "\(p.label!): let v\(i)" : "let v\(i)"
        }.joined(separator: ", ")

        let extractTuple = prismCase.parameters.enumerated().map { i, p in
            p.label != nil ? "\(p.label!): v\(i)" : "v\(i)"
        }.joined(separator: ", ")

        return """
        public var \(name): Optic_Primitives.Optic.Prism<\(root), (\(tupleTypes))> {
                    Optic_Primitives.Optic.Prism(
                        embed: { .\(name)(\(embedArgs)) },
                        extract: { if case .\(name)(\(extractPatterns)) = $0 { return (\(extractTuple)) } else { return nil } }
                    )
                }
        """
    }
}

// MARK: - Identifier Escaping

/// Escapes an identifier with backticks if it's a Swift keyword.
func escapeIdentifier(_ identifier: String) -> String {
    var identifier = identifier
    let isKeyword = identifier.withUTF8 { buffer in
        let text = SyntaxText(baseAddress: buffer.baseAddress, count: buffer.count)
        return Keyword(text) != nil
    }
    if isKeyword {
        return "`\(identifier)`"
    }
    return identifier
}
