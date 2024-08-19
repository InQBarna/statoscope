//
//  AllDeepPendingEffectsTest.swift
//  
//
//  Created by Sergi Hernanz on 28/1/24.
//

import Foundation
import Statoscope
@testable import StatoscopeTesting
import XCTest

// swiftlint:disable nesting
class AllDeepPendingEffectsTest: XCTestCase {

    enum SimpleParentChild {
        struct ParentEffect: Effect {
            func runEffect() async throws { () }
            typealias ResultType = Void
        }
        final class Parent: Statostore, Injectable, ObservableObject {
            typealias When = Void
            @Subscope var child: Child? = Child()
            let uuid: UUID = UUID()
            static var defaultValue: Parent = Parent()
            func update(_ when: Void) throws {
                effectsState.enqueue(ParentEffect())
            }
        }

        struct ChildEffect: Effect {
            func runEffect() async throws { () }
            typealias ResultType = Void
        }
        final class Child: Statostore, ObservableObject {
            typealias When = Void
            @Superscope var parent: Parent
            func update(_ when: Void) throws {
                effectsState.enqueue(ChildEffect())
            }
        }
    }

    func testSimpleParentChildAllDeepPendingEffects() throws {
        let parent = SimpleParentChild.Parent()
        parent.send(())
        parent.child?.send(())

        let allDeepOngoingEffects = parent.allDeepOngoingEffects()
        XCTAssertEqual(allDeepOngoingEffects.count, 2)
        let parentEffects = try XCTUnwrap(allDeepOngoingEffects["Parent"])
        let childEffects = try XCTUnwrap(allDeepOngoingEffects["Child"])
        XCTAssertEqual(parentEffects.count, 1)
        XCTAssertEqual(childEffects.count, 1)
        XCTAssert(parentEffects.first is SimpleParentChild.ParentEffect)
        XCTAssert(childEffects.first is SimpleParentChild.ChildEffect)

        parent.cancellAllDeepEffects()
        XCTAssert(parent.allDeepOngoingEffects().count == 0)
    }

    enum ParentChildGrandSon {
        struct ParentEffect: Effect {
            func runEffect() async throws { () }
            typealias ResultType = Void
        }
        final class Parent: Statostore, Injectable, ObservableObject {
            typealias When = Void
            func update(_ when: Void) throws {
                effectsState.enqueue(ParentEffect())
            }
            @Subscope var child: Child? = Child()
            static var defaultValue: Parent = Parent()
        }
        struct ChildEffect: Effect {
            func runEffect() async throws { () }
            typealias ResultType = Void
        }
        final class Child: Statostore, Injectable, ObservableObject {
            typealias When = Void
            func update(_ when: Void) throws {
                effectsState.enqueue(ChildEffect())
            }
            @Superscope var parent: Parent
            @Subscope var grandson: GrandSon? = GrandSon()
            static var defaultValue: Child = Child()
        }
        struct GrandSonEffect: Effect {
            func runEffect() async throws { () }
            typealias ResultType = Void
        }
        final class GrandSon: Statostore, ObservableObject {
            typealias When = Void
            func update(_ when: Void) throws {
                effectsState.enqueue(GrandSonEffect())
            }
            @Superscope var parent: Parent
            @Superscope var child: Child
        }
    }

    func testParentChildGrandSonAllDeepPendingEffects() throws {
        let parent = ParentChildGrandSon.Parent()
        parent.send(())
        parent.child?.send(())
        parent.child?.grandson?.send(())
        let allDeepOngoingEffects = parent.allDeepOngoingEffects()
        XCTAssertEqual(allDeepOngoingEffects.count, 3)
        let parentEffects = try XCTUnwrap(allDeepOngoingEffects["Parent"])
        let childEffects = try XCTUnwrap(allDeepOngoingEffects["Child"])
        let grandsonEffects = try XCTUnwrap(allDeepOngoingEffects["GrandSon"])
        XCTAssertEqual(parentEffects.count, 1)
        XCTAssertEqual(childEffects.count, 1)
        XCTAssertEqual(grandsonEffects.count, 1)
        XCTAssert(parentEffects.first is ParentChildGrandSon.ParentEffect)
        XCTAssert(childEffects.first is ParentChildGrandSon.ChildEffect)
        XCTAssert(grandsonEffects.first is ParentChildGrandSon.GrandSonEffect)

        parent.cancellAllDeepEffects()
        XCTAssert(parent.allDeepOngoingEffects().count == 0)
    }

}
// swiftlint:enable nesting
