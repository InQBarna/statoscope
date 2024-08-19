//
//  StateProtocolMacro.swift
//
//
//  Created by Sergi Hernanz on 16/3/24.
//

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct StateProtocolMacro: PeerMacro {
    public static func expansion<
        Context: MacroExpansionContext,
        Declaration: DeclSyntaxProtocol
    >(
        of node: AttributeSyntax,
        providingPeersOf declaration: Declaration,
        in context: Context
    ) throws -> [DeclSyntax] {

        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            throw StatoscopeMacroError.message("@StateProtocolMacro only works on classes")
        }

        let variableDecl = classDecl.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
        let protocolDeclaration = ProtocolDeclSyntax(name: .identifier(classDecl.name.text + "State")) {
            for varDecl in variableDecl {
                if let varName = varDecl.bindings.first?.pattern,
                   let varType = varDecl.bindings.first?.typeAnnotation?.type,
                   nil == varDecl.modifiers.first(where: { $0.name.text == "private" }) {
                    DeclSyntax(stringLiteral: "var \(varName): \(varType) { get }")
                }
            }
        }
        return [DeclSyntax(protocolDeclaration)]
    }
}
