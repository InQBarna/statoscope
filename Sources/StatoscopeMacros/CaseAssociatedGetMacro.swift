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
          throw StatoscopeMacroError.message("@EnumDeclSyntax only works on enums")
        }

        /*
        let enumCases = enumDecl.memberBlock.members
            .flatMap { caseSyntax in
                caseSyntax.decl.as(EnumCaseDeclSyntax.self)?.elements ?? []
            }
        
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
        
        return enumDecl.memberBlock.members
            .flatMap { caseSyntax in
                caseSyntax.decl.as(EnumCaseDeclSyntax.self)?.elements ?? []
            }
            .compactMap { caseDecl -> DeclSyntax? in
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
                    let associatedValues: [(label: String?, type: String)] = associatedDecl.map {
                        if let label = $0.firstName {
                            (label: "\(label.trimmed)", type: "\($0.type.trimmed)")
                        } else {
                            (label: nil, type: "\($0.type.trimmed)")
                        }
                    }
                    let caseLetAssign = associatedValues.enumerated().map {
                        if let label = $0.element.label {
                            "let \(label)"
                        } else {
                            "let param\($0.offset)"
                        }
                    }
                        .joined(separator: ",")
                    let returnDeclTuple = associatedValues.enumerated().map {
                        if let label = $0.element.label {
                            "\(label): \($0.element.type)"
                        } else {
                            "\($0.element.type)"
                        }
                    }
                        .joined(separator: ",")
                    let returnTuple = associatedValues.enumerated().map {
                        if let label = $0.element.label {
                            "\(label): \(label)"
                        } else {
                            "param\($0.offset)"
                        }
                    }
                        .joined(separator: ",")
                    return """
                    var \(caseDecl.name.trimmed): (\(raw: returnDeclTuple))? {
                        switch self {
                            case .\(caseDecl.name.trimmed)(\(raw: caseLetAssign)): 
                            return (\(raw: returnTuple))
                            default: return nil
                        }
                    }
                    """
                }
            }
    }
}

/*
 import SwiftSyntax
 import SwiftSyntaxBuilder
 import SwiftDiagnostics
 import SwiftCompilerPlugin

 @main
 struct CaseAssociatedGetPlugin: CompilerPlugin {
     let pluginName = "CaseAssociatedGetPlugin"

     func createMacros() -> [String : Macro.Type] {
         [
             "CaseAssociatedGet": CaseAssociatedGetMacro.self
         ]
     }
 }

 struct CaseAssociatedGetMacro: Macro {
     static func expansion(
         of node: AttributeSyntax,
         attachedTo declaration: DeclSyntax,
         in context: MacroExpansionContext
     ) -> DeclSyntax {
         guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
             context.diagnose(.init(message: "Can only be applied to enums", diagnosticID: .error, severity: .error), on: node)
             return declaration
         }

         var newMembers: [MemberDeclListItemSyntax] = []

         for caseDecl in enumDecl.memberBlock.members {
             guard let enumCaseDecl = caseElement.decl.as(EnumCaseDeclSyntax.self) else {
                 continue
             }

             for caseDecl in enumCaseDecl.elements {
                 if let associatedValues = caseDecl.associatedValue?.parameterList {
                     let propertyName = caseDecl.identifier.text
                     let paramDetails = associatedValues.map { param -> (String, String?) in
                         if let label = param.firstName {
                             return (label.text, param.type.description)
                         } else {
                             return ("associatedValue", param.type.description)
                         }
                     }

                     // Create tuple return type
                     let returnType = paramDetails.map { (label, type) in
                         if label == "associatedValue" {
                             return type ?? "Any"
                         } else {
                             return "\(label): \(type ?? "Any")"
                         }
                     }.joined(separator: ", ")

                     let returnTuple = paramDetails.map { (label, _) in
                         if label == "associatedValue" {
                             return "\(label)"
                         } else {
                             return "\(label)"
                         }
                     }.joined(separator: ", ")

                     // Generate the computed property with switch
                     let varDecl: DeclSyntax = """
                     var \(propertyName): (\(raw: returnType))? {
                         switch self {
                         case .\(caseElement.identifier)(\(raw: paramDetails.map { "\($0.0)" }.joined(separator: ", "))):
                             return (\(raw: returnTuple))
                         default:
                             return nil
                         }
                     }
                     """
                     newMembers.append(SyntaxFactory.makeMemberDeclListItem(decl: varDecl))
                 }
             }
         }

         var newEnumDecl = enumDecl
         newEnumDecl.memberBlock.members.append(contentsOf: newMembers)
         return DeclSyntax(newEnumDecl)
     }
 }

 extension String {
     func firstUppercased() -> String {
         return prefix(1).uppercased() + dropFirst()
     }
 }

 */
