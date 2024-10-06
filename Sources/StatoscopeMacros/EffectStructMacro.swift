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
            "@EffectStructMacro requires an function that returns a When"
          )
        }
         */

        let parameterList = funcDecl.signature.parameterClause.parameters
        let newGenericParameterClause = buildGenericParameterClause(funcDecl: funcDecl)
        let newStructDeclaration = StructDeclSyntax(
            name: .identifier(funcDecl.name.text.firstCharCapitalized + "Effect"),
            genericParameterClause: newGenericParameterClause,
            inheritanceClause: InheritanceClauseSyntax(
                inheritedTypes: InheritedTypeListSyntax {
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "Effect"))
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "Equatable"))
                }
            ),
            memberBlock: MemberBlockSyntax(
                members: MemberBlockItemListSyntax {
                    for param in parameterList {
                        MemberBlockItemSyntax(
                            decl: VariableDeclSyntax(
                                bindingSpecifier: .keyword(Keyword.let),
                                bindings: [
                                    PatternBindingSyntax(
                                        pattern: IdentifierPatternSyntax(identifier: param.secondName ?? param.firstName),
                                        typeAnnotation: TypeAnnotationSyntax(type: param.type)
                                    )
                                ]
                            )
                        )
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
                                            "\(param.firstName): \(param.secondName ?? param.firstName)"
                                        }).joined(separator: ", ") +
                                        ")"
                                    )
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
}
