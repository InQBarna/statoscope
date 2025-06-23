//
//  Macros.swift
//  
//
//  Created by Sergi Hernanz on 16/3/24.
//

import Foundation

@attached(peer, names: arbitrary)
public macro EffectStruct(
    equatable: Bool = false
) = #externalMacro(module: "StatoscopeMacros", type: "EffectStructMacro")

@attached(member, names: arbitrary)
public macro CaseAssociatedGet() = #externalMacro(module: "StatoscopeMacros", type: "CaseAssociatedGetMacro")

@attached(member, names: arbitrary)
public macro Copy() = #externalMacro(module: "StatoscopeMacros", type: "CopyMacro")
