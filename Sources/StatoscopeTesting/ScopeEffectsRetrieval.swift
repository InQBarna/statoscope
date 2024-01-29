//
//  StateScopeLibraryTests.swift
//  familymealplan
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import Statoscope

extension Scope {
    
    func allDeepPendingEffects() -> [String: [any Effect]] {
        return Dictionary(
            allChildScopes().compactMap{
                let effects = $0.effects
                guard effects.count > 0 else {
                    return nil
                }
                return ("\($0)", effects)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }
    
    func clearAllDeepPendingEffects() {
        allChildScopes()
            .forEach { $0.clearPending() }
    }
}
