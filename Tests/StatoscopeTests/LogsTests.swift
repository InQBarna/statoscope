//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 18/2/24.
//

import Foundation
import XCTest
@testable import Statoscope
import StatoscopeTesting
import CustomDump

final class LogsTests: XCTestCase {
    
    private enum ParentChild {
        final class Parent: Statostore {
            var loading: Bool = false
            @Subscope var child: Child?
            typealias When = Void
            func update(_ when: When) throws { }
        }
        
        final class Child: Statostore {
            var showingChild: Bool = false
            typealias When = Void
            func update(_ when: Void) throws { }
        }
    }
    
    func testLogState() throws {
        let sut = ParentChild.Parent()
        let expectedDescription = """
Parent(
  loading: false
  _child: nil
)
"""
        let description = String(describing: sut)
        XCTAssertEqual(description, expectedDescription)
    }
    
    func testLogChildren() throws {
        let sut = ParentChild.Parent()
        sut.child = ParentChild.Child()
        let expectedDescription = """
Parent(
  loading: false
  _child: Child(
    showingChild: false
  )
)
"""
        let description = String(describing: sut)
        XCTAssertEqual(description, expectedDescription)
    }
    
    private enum ParentChildGrandSon {
        final class Parent: Statostore {
            var loading: Bool = false
            @Subscope var child: Child?
            typealias When = Void
            func update(_ when: Void) throws {}
        }
        
        final class Child: Statostore {
            var showingChild: Bool = false
            @Subscope var grandson: GrandSon?
            typealias When = Void
            func update(_ when: Void) throws { }
        }
        
        final class GrandSon: Statostore {
            var someVar: String = "someVarValue"
            typealias When = Void
            func update(_ when: Void) throws { }
        }
    }
    
    func testLogChildrenGrandson() throws {
        let sut = ParentChildGrandSon.Parent()
        sut.child = ParentChildGrandSon.Child()
        sut.child?.grandson = ParentChildGrandSon.GrandSon()
        let expectedDescription = """
Parent(
  loading: false
  _child: Child(
    showingChild: false
    _grandson: GrandSon(
      someVar: someVarValue
    )
  )
)
"""
        let description = String(describing: sut)
        XCTAssertEqual(description, expectedDescription)
    }
    
    
    private struct MyEffect: Effect, Equatable {
        let milliseconds: UInt64
        func runEffect() async throws {
            try await Task.sleep(nanoseconds: milliseconds * 1000_000)
        }
    }
    
    final class ScopeWithEffect: Statostore {
        var loading: Bool = false
        enum When {
            case sendWaitEffect
            case anyEffectCompleted
        }
        func update(_ when: When) throws {
            switch when {
            case .sendWaitEffect:
                loading = true
                effectsState.enqueue(MyEffect(milliseconds: 1000).map {
                    .anyEffectCompleted
                })
            case .anyEffectCompleted:
                loading = false
            }
        }
    }
    
    func testLogEffects() throws {
        let sut = ScopeWithEffect()
        XCTAssertEqual(
            String(describing: sut),
"""
ScopeWithEffect(
  loading: false
)
""")
        sut.send(.sendWaitEffect)
        XCTAssertEqual(
            String(describing: sut),
"""
ScopeWithEffect(
  loading: true
  effects: [
  MyEffect(milliseconds: 1000)
  ]
)
""")
        sut.send(.sendWaitEffect)
        XCTAssertEqual(
            String(describing: sut),
"""
ScopeWithEffect(
  loading: true
  effects: [
  MyEffect(milliseconds: 1000)
  MyEffect(milliseconds: 1000)
  ]
)
""")
    }
}
