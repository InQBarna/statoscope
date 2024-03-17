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

        // This only makes sense non-void functions
        guard let returnType = funcDecl.signature.returnClause?.type,
              returnType.as(IdentifierTypeSyntax.self)?.name.text != "Void" else {
          throw StatoscopeMacroError.message(
            "@EffectStructMacro requires an function that returns a When"
          )
        }

        let parameterList = funcDecl.signature.parameterClause.parameters
        let newStructDeclaration = StructDeclSyntax(
            name: .identifier(funcDecl.name.text.firstCharCapitalized + "Effect"),
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
}
