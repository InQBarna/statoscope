//
//  CaseAssociatedGetMacro.swift
//
//
//  Created by Sergi Hernanz on 2/5/24.
//
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct CaseAssociatedGetMacro: MemberMacro {
    public static func expansion(
      of node: AttributeSyntax,
      providingMembersOf declaration: some DeclGroupSyntax,
      in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        // Only on functions at the moment.
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
          throw StatoscopeMacroError.message("@EnumDeclSyntax only works on functions")
        }

        let enumCases = enumDecl.memberBlock.members
            .flatMap { caseSyntax in
                caseSyntax.decl.as(EnumCaseDeclSyntax.self)?.elements ?? []
            }
        
        /*
        let newMemberDeclaration = MemberBlockItemSyntax {
            VariableDeclSyntax(
                bindingSpecifier: .keyword(Keyword.var),
                bindings: PatternBindingListSyntax {
                    PatternBindingSyntax(
                        pattern: .identifier(firstCase.id),
                        accessorBlock: AccessorBlockSyntax(
                            accessors: CodeBlockSyntax(
                                statements: CodeBlockItemListSyntax(
                                )
                            )
                        )
                    )
                }
            )
        }
         */
        
        return enumCases
            .compactMap { caseDecl in
                guard let associatedDecl = caseDecl.parameterClause?.parameters,
                      let associatedDeclFirstParameter = associatedDecl.first else {
                    return nil
                }
                if associatedDecl.count == 1 {
                    return """
                    var \(caseDecl.name.trimmed): \(associatedDeclFirstParameter.type.trimmed)? {
                        switch self {
                            case .\(caseDecl.name.trimmed)(let associatedValue): return associatedValue
                            default: return nil
                        }
                    }
                    """
                } else {
                    return """
                    var \(caseDecl.name.trimmed): (\(raw: associatedDecl.map { "\($0.type.trimmed)" }.joined(separator: ",")))? {
                        switch self {
                            case .\(caseDecl.name.trimmed)(let associatedValue): return associatedValue
                            default: return nil
                        }
                    }
                    """
                }
            }
    }
}
