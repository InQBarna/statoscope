//
//  StatoscopeMacrosPlugin.swift
//
//
//  Created by Sergi Hernanz on 16/3/24.
//

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct StatoscopeMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        EffectStructMacro.self,
        StateProtocolMacro.self,
        CaseAssociatedGetMacro.self
    ]
}
