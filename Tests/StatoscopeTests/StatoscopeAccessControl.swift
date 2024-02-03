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
        print("In this class we'd like to know which lines compile and which don't")
    }
    
    private enum When {
        case exampleWhen1
    }
    // Does not compile
    // let handler: EffectsHandler<When> = EffectsHandler<When>()
    
    private final class DummyScope: Scope {
        enum When {
            case delayFinished
        }
        func update(_ when: When) throws {
            effectsHandler.enqueue(AnyEffect {
                try await Task.sleep(nanoseconds: 1_000_000)
                return When.delayFinished
            })
            
            // Does not compile, internal
            // runEnqueuedEffectAndGetWhenResults { _, _ in return }
            
            // TODO: it should better not compile ... it's better to expose the effectsHandler
            //  as the only method to handle effects
            enqueue(AnyEffect {
                try await Task.sleep(nanoseconds: 1_000_000)
                return When.delayFinished
            })
            
            // TODO: it should better not compile does not make sense to send during update
            self.send(.delayFinished)
            
            // TODO: it should better not compile does not make sense to send during update
            _ = try self.sendUnsafe(.delayFinished)
            
            // TODO: it should better not compile does not make sense to update during update
            try self.update(.delayFinished)
            
            // TODO: it should better not compile does not make sense to addMiddleware
            self.addMiddleWare { _, _ in nil }
            
            // This may compile... should be used only for debugging
            _ = self.parentNode
            _ = self.childrenNodes
            _ = self.rootNode
            
            // This may compile
            self.injectObject(Date())
            let _: Date = try self.resolveUnsafe()
        }
    }
}
