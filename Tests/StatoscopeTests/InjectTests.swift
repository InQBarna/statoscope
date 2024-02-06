//
//  InjectTests.swift
//  familymealplanTests
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import XCTest
@testable import Statoscope

class SubscopeSuperscodePropertyWrapperTests: XCTestCase {

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

    func testSimpleParentChildInjection() {
        let parent = SimpleParentChild.Parent()
        XCTAssert(parent.child?.parent === parent)
    }

    enum ParentChildGrandSon {
        final class Parent: InjectionTreeNode, Injectable, ObservableObject {
            @Subscope var child: Child? = Child()
            static var defaultValue: Parent = Parent()
        }
        final class Child: InjectionTreeNode, Injectable, ObservableObject {
            @Superscope var parent: Parent
            @Subscope var grandson: GrandSon? = GrandSon()
            static var defaultValue: Child = Child()
        }
        final class GrandSon: InjectionTreeNode, ObservableObject {
            @Superscope var parent: Parent
            @Superscope var child: Child
        }
    }

    func testParentGrandSonInjection() {
        let parent = ParentChildGrandSon.Parent()
        XCTAssert(parent.child?.grandson?.parent === parent)
    }

    func testTwoIndependentTreesInjection() {
        let parent = ParentChildGrandSon.Parent()
        let parent2 = ParentChildGrandSon.Parent()
        XCTAssert(parent.child?.grandson?.parent === parent)
        XCTAssert(parent2.child?.grandson?.parent === parent2)
    }

    enum TwoSubhierarchies {
        final class Parent: InjectionTreeNode, Injectable, ObservableObject {
            @Subscope var child1: Child? = Child()
            @Subscope var child2: Child? = Child()
            static var defaultValue: Parent = Parent()
        }
        final class Child: InjectionTreeNode, Injectable, ObservableObject {
            @Subscope var grandson: GrandSon? = GrandSon()
            static var defaultValue: Child = Child()
        }
        final class GrandSon: InjectionTreeNode, ObservableObject {
            @Superscope var parent: Parent
            @Superscope var child: Child
        }
    }

    func testTwoSubhierarchies() {
        let parent = TwoSubhierarchies.Parent()
        XCTAssert(parent.child1?.grandson?.parent === parent)
        XCTAssert(parent.child1?.grandson?.child === parent.child1)
        XCTAssert(parent.child2?.grandson?.parent === parent)
        XCTAssert(parent.child2?.grandson?.child === parent.child2)
    }

    func testInjectionNotFoundReturnsDefaultValue() {
        let child = SimpleParentChild.Child()
        XCTAssertEqual(child.parent.uuid, SimpleParentChild.Parent.defaultValue.uuid)
    }

    // Otras cosas a cubrir:
    //  mensaje correcto para el developer cuando no se encuentra el superscope
}

class ForcedInjectSuperscopeTests: XCTestCase {

    enum UnrelatedScopes {
        final class First: Statostore, Injectable, ObservableObject {
            typealias When = Void
            let uuid: UUID = UUID()
            static var defaultValue: First = First()
            func update(_ when: Void) throws { }
        }
        final class Second: Statostore, ObservableObject {
            typealias When = Void
            @Superscope var parent: First
            func update(_ when: Void) throws { }
        }
    }

    func testForcedInjectionSingleScope() {
        let parent = UnrelatedScopes.First()
        let child = UnrelatedScopes.Second()
        // Before injection call, injected value is the defaultValue
        XCTAssertEqual(child.parent.uuid, UnrelatedScopes.First.defaultValue.uuid)
        child.injectSuperscope(parent)
        // After injection, correct value
        XCTAssertEqual(child.parent.uuid, parent.uuid)
    }

    func testOverwriteInjectionSingleScope() {
        let parent = UnrelatedScopes.First()
        let child = UnrelatedScopes.Second()
        child.parent = parent
        // After injection, correct value
        XCTAssertEqual(child.parent.uuid, parent.uuid)
    }

    enum ParentChildGrandSon {
        final class Parent: InjectionTreeNode, Injectable, ObservableObject {
            @Subscope var child: Child? = Child()
            static var defaultValue: Parent = Parent()
        }
        final class Child: InjectionTreeNode, Injectable, ObservableObject {
            @Superscope var parent: Parent
            @Subscope var grandson: GrandSon? = GrandSon()
            static var defaultValue: Child = Child()
        }
        final class GrandSon: InjectionTreeNode, ObservableObject {
            @Superscope var parent: Parent
            @Superscope var child: Child
            @Superscope var injected: UnrelatedScopes.First
        }
    }

    func testForcedInjectionInGrandSonHierarchy() {
        let injected = UnrelatedScopes.First()
        let parent = ParentChildGrandSon.Parent()
        // Before injection call, injected value is the defaultValue
        XCTAssertEqual(parent.child?.grandson?.injected.uuid, UnrelatedScopes.First.defaultValue.uuid)
        parent.injectSuperscope(injected)
        // After injection, correct value
        XCTAssertEqual(parent.child?.grandson?.injected.uuid, injected.uuid)
    }

    // Otras cosas a cubrir:
    //  Llamar a injectSuperscope cuando en realidad ya es un superscope
    //   Gestionar problemas de memoria en el punto anterior?
    //  Algun problema de memoria en el caso normal ?
}

class InjectObjectTests: XCTestCase {

    final class InjectableClass: Injectable {
        let uuid: UUID = UUID()
        static var defaultValue: InjectableClass = InjectableClass()
    }
    struct InjectableStruct: Injectable {
        let uuid: UUID = UUID()
        static var defaultValue: InjectableStruct = InjectableStruct()
    }
    final class ScopeWihInjectables: Statostore, ObservableObject {
        typealias When = Void
        @Injected var injectedStruct: InjectableStruct
        @Injected var injectedClass: InjectableClass
        func update(_ when: Void) throws { }
    }

    func testInjectClass() {
        let sut = ScopeWihInjectables()

        // Returns default value before injection
        //  an internally catched exception is thrown, debugger will stop if excp. breakpoint enabled
        XCTAssertEqual(sut.injectedClass.uuid, InjectableClass.defaultValue.uuid)

        // Returns injected class after injection
        let injectableClass = InjectableClass()
        sut.injectObject(injectableClass)
        XCTAssertEqual(sut.injectedClass.uuid, injectableClass.uuid)
    }

    func testInjectStruct() {
        let injectableStruct = InjectableStruct()
        let sut = ScopeWihInjectables()
        XCTAssertEqual(sut.injectedStruct.uuid, InjectableStruct.defaultValue.uuid)
        sut.injectObject(injectableStruct)
        XCTAssertEqual(sut.injectedStruct.uuid, injectableStruct.uuid)
    }

    func testInjectPtotocol() {
        // TODO: Protocols can't be injected, create protocolwitness macro
    }

    enum ParentChildGrandSon {
        final class Parent: InjectionTreeNode, Injectable, ObservableObject {
            @Subscope var child: Child? = Child()
            static var defaultValue: Parent = Parent()
        }
        final class Child: InjectionTreeNode, Injectable, ObservableObject {
            @Superscope var parent: Parent
            @Subscope var grandson: GrandSon? = GrandSon()
            static var defaultValue: Child = Child()
        }
        final class GrandSon: InjectionTreeNode, ObservableObject {
            @Superscope var parent: Parent
            @Superscope var child: Child
            @Injected var injectedStruct: InjectableStruct
            @Injected var injectedClass: InjectableClass
        }
    }

    func testInjectClassInGrandsonHierarchy() {
        let injectableClass = InjectableClass()
        let sut = ParentChildGrandSon.Parent()
        XCTAssertEqual(sut.child?.grandson?.injectedClass.uuid, InjectableClass.defaultValue.uuid)
        sut.injectObject(injectableClass)
        XCTAssertEqual(sut.child?.grandson?.injectedClass.uuid, injectableClass.uuid)
    }

    func testInjectStructInGrandsonHierarchy() {
        let injectableStruct = InjectableStruct()
        let sut = ParentChildGrandSon.Parent()
        XCTAssertEqual(sut.child?.grandson?.injectedStruct.uuid, InjectableStruct.defaultValue.uuid)
        sut.injectObject(injectableStruct)
        XCTAssertEqual(sut.child?.grandson?.injectedStruct.uuid, injectableStruct.uuid)
    }

    enum ParentChildGrandSonAccessAtAllLevels {
        final class Parent: InjectionTreeNode, Injectable, ObservableObject {
            @Subscope var child: Child? = Child()
            @Injected var injectedStruct: InjectableStruct
            @Injected var injectedClass: InjectableClass
            static var defaultValue: Parent = Parent()
        }
        final class Child: InjectionTreeNode, Injectable, ObservableObject {
            @Superscope var parent: Parent
            @Subscope var grandson: GrandSon? = GrandSon()
            @Injected var injectedStruct: InjectableStruct
            @Injected var injectedClass: InjectableClass
            static var defaultValue: Child = Child()
        }
        final class GrandSon: InjectionTreeNode, ObservableObject {
            @Superscope var parent: Parent
            @Superscope var child: Child
            @Injected var injectedStruct: InjectableStruct
            @Injected var injectedClass: InjectableClass
        }
    }

    func testTwoDifferentInjectsInGrandsonHierarchy() {
        let injectableStruct = InjectableStruct()
        let injectableStruct2 = InjectableStruct()
        let sut = ParentChildGrandSonAccessAtAllLevels.Parent()
        XCTAssertEqual(sut.injectedStruct.uuid, InjectableStruct.defaultValue.uuid)
        XCTAssertEqual(sut.child?.injectedStruct.uuid, InjectableStruct.defaultValue.uuid)
        XCTAssertEqual(sut.child?.grandson?.injectedStruct.uuid, InjectableStruct.defaultValue.uuid)
        sut.injectObject(injectableStruct)
        XCTAssertEqual(sut.injectedStruct.uuid, injectableStruct.uuid)
        XCTAssertEqual(sut.child?.injectedStruct.uuid, injectableStruct.uuid)
        XCTAssertEqual(sut.child?.grandson?.injectedStruct.uuid, injectableStruct.uuid)
        sut.child?.injectObject(injectableStruct2)
        XCTAssertEqual(sut.injectedStruct.uuid, injectableStruct.uuid)
        XCTAssertEqual(sut.child?.injectedStruct.uuid, injectableStruct2.uuid)
        XCTAssertEqual(sut.child?.grandson?.injectedStruct.uuid, injectableStruct2.uuid)
    }

    // Otras cosas a cubrir:
    //  Gestion de memoria para clases ?
}
