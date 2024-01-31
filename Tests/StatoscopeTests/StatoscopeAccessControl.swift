//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 31/1/24.
//

import Foundation
import XCTest
import Statoscope

class StatoscopeAccessControl: XCTestCase {
    
    func testPrivateClasses() {
        enum When {
            case exampleWhen1
        }
        // Does not compile
        // let handler: EffectsHandler<When> = EffectsHandler<When>()
    }
}
