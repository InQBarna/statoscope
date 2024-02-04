//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 28/1/24.
//

import Foundation
import Statoscope
@testable import StatoscopeTesting
import XCTest

class ScopeTreeRetrievalTests: XCTestCase {
    
    enum SimpleParentChild {
        final class Parent: Statostore, Injectable, ObservableObject {
            typealias When = Void
            @Subscope var child: Child? = Child()
            let uuid: UUID = UUID()
            static var defaultValue: Parent = Parent()
            func update(_ when: Void) throws { }
        }
        final class Child: Statostore, ObservableObject {
            typealias When = Void
            @Superscope var parent: Parent
            func update(_ when: Void) throws { }
        }
    }
    
    func testSimpleParentChildAllChildScopes() {
        let parent = SimpleParentChild.Parent()
        let allChildScopes = parent.allChildScopes()
        XCTAssertEqual(allChildScopes.count, 2)
        XCTAssert(allChildScopes.first ===  parent)
        XCTAssert(allChildScopes.last === parent.child)
    }
    
    enum ParentChildGrandSon {
        final class Parent: Statostore, Injectable, ObservableObject {
            typealias When = Void
            func update(_ when: Void) throws { }
            @Subscope var child: Child? = Child()
            static var defaultValue: Parent = Parent()
        }
        final class Child: Statostore, Injectable, ObservableObject {
            typealias When = Void
            func update(_ when: Void) throws { }
            @Superscope var parent: Parent
            @Subscope var grandson: GrandSon? = GrandSon()
            static var defaultValue: Child = Child()
        }
        final class GrandSon: Statostore, ObservableObject {
            typealias When = Void
            func update(_ when: Void) throws { }
            @Superscope var parent: Parent
            @Superscope var child: Child
        }
    }
    
    func testParentChildGrandSonAllChildScopes() {
        let parent = ParentChildGrandSon.Parent()
        let allChildScopes = parent.allChildScopes()
        XCTAssertEqual(allChildScopes.count, 3)
        XCTAssert(allChildScopes.first ===  parent)
        XCTAssert(allChildScopes[1] === parent.child)
        XCTAssert(allChildScopes.last === parent.child?.grandson)
    }
    
}
