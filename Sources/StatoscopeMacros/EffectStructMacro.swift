//
//  EffectStructMacro.swift
//
//
//  Created by Sergi Hernanz on 16/3/24.
//

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

extension String {
    var firstCharCapitalized: String {
        guard let firstChar = self.first else {
            return ""
        }
        let secondIndex = self.index(after: self.startIndex)
        let excludingFirst = self[secondIndex..<self.endIndex]
        return firstChar.uppercased() + excludingFirst
    }
}

extension SyntaxProtocol {
    var trimm: Self {
        self
            .trimmed
            .with(\.leadingTrivia, [])
            .with(\.trailingTrivia, [])
    }
}

extension FunctionParameterSyntax {
    var trimm: Self {
        self
        .with(\.firstName, firstName.trimmed)
        .with(\.secondName, secondName?.trimmed)
    }
}

extension AttributeSyntax {
    static func effectInjection() -> AttributeSyntax {
        .init(
            atSign: .atSignToken(),
            attributeName: IdentifierTypeSyntax(name: .identifier("InjectedForEffect"))
        )
    }
}

public struct EffectStructMacro: PeerMacro {
    public static func expansion<
        Context: MacroExpansionContext,
        Declaration: DeclSyntaxProtocol
    >(
        of node: AttributeSyntax,
        providingPeersOf declaration: Declaration,
        in context: Context
    ) throws -> [DeclSyntax] {

        // Only on functions at the moment.
        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
          throw StatoscopeMacroError.message("@EffectStructMacro only works on functions")
        }

        // This only makes sense non-void functions ??
        /*
        guard let returnType = funcDecl.signature.returnClause?.type,
            returnType.as(IdentifierTypeSyntax.self)?.name.text != "Void" else {
          throw StatoscopeMacroError.message(
            "@EffectStructMacro requires a function that returns a When"
          )
        }
         */

        let equatableRequested: Bool = extractEquatableParam(from: node)
        let parameterList = funcDecl.signature.parameterClause.parameters
        let newGenericParameterClause = buildGenericParameterClause(funcDecl: funcDecl)
        let injectedAttr = AttributeSyntax(
            atSign: .atSignToken(),
            attributeName: IdentifierTypeSyntax(name: .identifier("InjectedForEffect"))
        )
        let newStructDeclaration = StructDeclSyntax(
            modifiers: DeclModifierListSyntax {
                DeclModifierSyntax(name: .keyword(.public))
            },
            name: .identifier(funcDecl.name.text.firstCharCapitalized + "Effect"),
            genericParameterClause: newGenericParameterClause,
            inheritanceClause: InheritanceClauseSyntax(
                inheritedTypes: InheritedTypeListSyntax {
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "Effect"))
                    if equatableRequested {
                        InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "Equatable"))
                    }
                }
            ),
            memberBlock: MemberBlockSyntax(
                members: MemberBlockItemListSyntax {
                    for param in parameterList {
                        let isInjectedForEffect: Bool = param.isInjectedForEffect(context: context)
                        if isInjectedForEffect {
                            MemberBlockItemSyntax(
                                decl: VariableDeclSyntax(
                                    attributes: [.attribute(injectedAttr)],
                                    bindingSpecifier: .keyword(Keyword.var),
                                    bindings: [
                                        PatternBindingSyntax(
                                            pattern: IdentifierPatternSyntax(identifier: param.secondName?.trimm ?? param.firstName.trimm),
                                            typeAnnotation: TypeAnnotationSyntax(
                                                colon: .colonToken(),
                                                type: param.type
                                            )
                                        )
                                    ]
                                )
                            )
                        } else {
                            MemberBlockItemSyntax(
                                decl: VariableDeclSyntax(
                                    bindingSpecifier: .keyword(Keyword.let),
                                    bindings: [
                                        PatternBindingSyntax(
                                            pattern: IdentifierPatternSyntax(identifier: param.secondName?.trimm ?? param.firstName.trimm),
                                            typeAnnotation: TypeAnnotationSyntax(type: param.type)
                                        )
                                    ]
                                )
                            )
                        }
                    }
                    MemberBlockItemSyntax(
                        decl: FunctionDeclSyntax(
                            attributes: funcDecl.attributes.filter {
                                switch $0 {
                                case .attribute(let at):
                                    return !at.attributeName.description.contains("EffectStruct")
                                case .ifConfigDecl:
                                    return true
                                }
                            },
                            modifiers: DeclModifierListSyntax {
                                DeclModifierSyntax(name: .keyword(.public))
                            },
                            name: "runEffect",
                            signature: FunctionSignatureSyntax(
                                parameterClause: FunctionParameterClauseSyntax {},
                                effectSpecifiers: FunctionEffectSpecifiersSyntax(
                                    asyncSpecifier: .keyword(.async),
                                    throwsSpecifier: .keyword(.throws)
                                ),
                                returnClause: funcDecl.signature.returnClause
                            ),
                            body: CodeBlockSyntax(
                                statements: CodeBlockItemListSyntax {
                                    CodeBlockItemSyntax(
                                        stringLiteral: "try await \(funcDecl.name)(" +
                                        parameterList.map({ param in
                                            "\(param.firstName.trimm): " +
                                            "\(param.secondName?.trimm ?? param.firstName.trimm)"
                                        }).joined(separator: ", ") +
                                        ")"
                                    )
                                }
                            )
                        )
                    )
                    MemberBlockItemSyntax(
                        decl: InitializerDeclSyntax(
                            modifiers: DeclModifierListSyntax {
                                DeclModifierSyntax(name: .keyword(.public))
                            },
                            signature: FunctionSignatureSyntax(
                                parameterClause: FunctionParameterClauseSyntax(
                                    leftParen: .leftParenToken(),
                                    parameters: FunctionParameterListSyntax {
                                        for param in parameterList {
                                            if !param.isInjectedForEffect(context: context) {
                                                param.trimm
                                            }
                                        }
                                    },
                                    rightParen: .rightParenToken()
                                )
                            ),
                            body: CodeBlockSyntax(
                                statements: CodeBlockItemListSyntax {
                                    for param in parameterList {
                                        if !param.isInjectedForEffect(context: context) {
                                            let stringLit = param.secondName?.trimm ?? param.firstName.trimm
                                            CodeBlockItemSyntax(
                                                stringLiteral: "self.\(stringLit.trimm) = \(stringLit.trimm)"
                                            )
                                        }
                                    }
                                }
                            )
                        )
                    )
                }
            )
        )
        return [DeclSyntax(newStructDeclaration)]
    }

    private static func buildGenericParameterClause(funcDecl: FunctionDeclSyntax) -> GenericParameterClauseSyntax? {
        let functionParmTypes: [String] = funcDecl.signature.parameterClause.parameters
            .compactMap {
                let typeSyntax = $0.type.as(OptionalTypeSyntax.self)?.wrappedType ?? $0.type
                guard let identifierTypeSyntax = typeSyntax.as(IdentifierTypeSyntax.self) else {
                    return nil
                }
                return identifierTypeSyntax.name.text
            }
        return funcDecl.genericParameterClause.map { existing in
            GenericParameterClauseSyntax(
                leftAngle: existing.leftAngle,
                parameters: GenericParameterListSyntax(
                    existing.parameters.map { existingParam in

                        let currentParamIsGeneric = functionParmTypes.contains(existingParam.name.text)
                        if currentParamIsGeneric,
                           let existingParamInheritanceComposed = existingParam.inheritedType?.as(CompositionTypeSyntax.self) {
                            guard nil == existingParamInheritanceComposed.elements.first(where: {
                                $0.type.as(IdentifierTypeSyntax.self)?.name.text == "Equatable"
                            }) else {
                                return GenericParameterSyntax(
                                    attributes: existingParam.attributes,
                                    name: existingParam.name,
                                    colon: existingParam.colon,
                                    inheritedType: existingParamInheritanceComposed,
                                    trailingComma: existingParam.trailingComma
                                )
                            }
                            var newComposed = existingParamInheritanceComposed.elements.map { existingGeneric in
                                CompositionTypeElementSyntax(
                                    type: existingGeneric.type,
                                    ampersand: .binaryOperator("&")
                                )
                            }
                            newComposed.append(
                                CompositionTypeElementSyntax(
                                    type: IdentifierTypeSyntax(name: .identifier("Equatable"))
                                )
                            )
                            let newInheritedType = CompositionTypeSyntax(
                                leadingTrivia: existingParamInheritanceComposed.leadingTrivia,
                                elements: CompositionTypeElementListSyntax(newComposed),
                                trailingTrivia: existingParamInheritanceComposed.trailingTrivia
                            )
                            return GenericParameterSyntax(
                                attributes: existingParam.attributes,
                                name: existingParam.name,
                                colon: existingParam.colon,
                                inheritedType: newInheritedType,
                                trailingComma: existingParam.trailingComma
                            )

                        } else if currentParamIsGeneric,
                               let existingInheritance = existingParam.inheritedType {
                            return GenericParameterSyntax(
                                attributes: existingParam.attributes,
                                name: existingParam.name,
                                colon: existingParam.colon,
                                inheritedType: CompositionTypeSyntax(
                                    elements: [
                                        CompositionTypeElementSyntax(
                                            type: existingInheritance,
                                            ampersand: .binaryOperator("&")
                                        ),
                                        CompositionTypeElementSyntax(
                                            type: IdentifierTypeSyntax(name: .identifier("Equatable"))
                                        )
                                    ]
                                ),
                                trailingComma: existingParam.trailingComma
                            )
                        } else {
                            return existingParam
                        }
                    }
                )
            )
        }
    }

    static func extractEquatableParam(
      from node: AttributeSyntax
    ) -> Bool {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let equatableArgument = arguments.first(where: { $0.label?.text == "equatable" }),
              let booleanExpression = equatableArgument.expression.as(BooleanLiteralExprSyntax.self) else {
            return false
        }
        return booleanExpression.literal.text == "true"
    }
}

extension FunctionParameterSyntax {
    func isInjectedForEffect(
        context: some MacroExpansionContext
    ) -> Bool {
        return attributes.contains(where: {
            guard case let .attribute(attr) = $0 else { return false }
            return attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "InjectedParam"
        })
    }
}
