//
//  StateScopeLibraryTests.swift
//  familymealplan
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
@testable import Statoscope

extension ScopeImplementation {

    func allDeepOngoingEffects() -> [String: [any Effect]] {
        return Dictionary(
            allChildScopes().compactMap {
                let effects = $0.effects
                guard effects.count > 0 else {
                    return nil
                }
                return ("\(type(of: $0))", effects)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func cancellAllDeepEffects() {
        allChildScopes()
            .forEach { $0.resetEffects() }
    }
}
