//
//  InjectTests.swift
//  familymealplanTests
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import XCTest
@_spi(SCT) @testable import Statoscope

// swiftlint:disable nesting
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

    func testSimpleParentChildRoot() {
        let sut = SimpleParentChild.Parent()
        XCTAssert(sut.child?.root === sut)
    }

    func testSimpleParentChildRootKePath() {
        let sut = SimpleParentChild.Parent()
        XCTAssertEqual(sut.child?.selfRootKeyPath, \SimpleParentChild.Parent.child)
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

    func testParentGrandSonRoot() {
        let sut = ParentChildGrandSon.Parent()
        XCTAssert(sut.child?.root === sut)
        XCTAssert(sut.child?.grandson?.root === sut)
    }

    func testParentGrandSonRootKePath() {
        let sut = ParentChildGrandSon.Parent()
        XCTAssertEqual(sut.child?.selfRootKeyPath, \ParentChildGrandSon.Parent.child)
        XCTAssertEqual(sut.child?.grandson?.selfRootKeyPath, \ParentChildGrandSon.Parent.child!.grandson)
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

    func testTwoSubhierarchiesRoot() {
        let sut = TwoSubhierarchies.Parent()
        XCTAssert(sut.child1?.root === sut)
        XCTAssert(sut.child1?.grandson?.root === sut)
        XCTAssert(sut.child2?.root === sut)
        XCTAssert(sut.child2?.grandson?.root === sut)
    }

    func testTwoSubhierarchiesRootKePath() {
        let sut = TwoSubhierarchies.Parent()
        XCTAssertEqual(sut.child1?.selfRootKeyPath, \TwoSubhierarchies.Parent.child1)
        XCTAssertEqual(sut.child1?.grandson?.selfRootKeyPath, \TwoSubhierarchies.Parent.child1!.grandson)
        XCTAssertEqual(sut.child2?.selfRootKeyPath, \TwoSubhierarchies.Parent.child2)
        XCTAssertEqual(sut.child2?.grandson?.selfRootKeyPath, \TwoSubhierarchies.Parent.child2!.grandson)
    }

    // Otras cosas a cubrir:
    //  mensaje correcto para el developer cuando no se encuentra el superscope

    // MARK: - `@_spi(SCT)` tree-introspection surface (_rootNode / _childrenNodes)

    func testRootNodeSPI() {
        let sut = ParentChildGrandSon.Parent()
        // Trigger lazy wiring by reading down to the grandson first.
        _ = sut.child?.grandson
        XCTAssert((sut.child?.grandson?._rootNode as AnyObject?) === sut)
    }

    func testChildrenNodesSPI() {
        let sut = ParentChildGrandSon.Parent()
        _ = sut.child?.grandson
        let children = sut._childrenNodes
        XCTAssertEqual(children.count, 1)
        guard let firstChild = children.first as? InjectionTreeNodeBox else {
            XCTFail("Expected exactly one child node, boxed as InjectionTreeNodeBox")
            return
        }
        // Recursing into the returned box exercises InjectionTreeNodeBox's own
        // _rootNode/_childrenNodes (delegating to anyLink), not just the top-level SPI vars.
        XCTAssert((firstChild._rootNode as AnyObject?) === sut)
        XCTAssertEqual(firstChild._childrenNodes.count, 1)
    }

    func testOptionalWrapperChildrenAndRootNodeSPI() {
        let sut = ParentChildGrandSon.Parent()
        let childOptional: ParentChildGrandSon.Child? = sut.child
        _ = childOptional?.grandson
        // Calling these directly on an Optional-typed variable exercises the conditional
        // `Optional: InjectionTreeNodeProtocol where Wrapped: InjectionTreeNode` conformance's
        // own _childrenNodes/_rootNode (`self?._childrenNodes` / `self?._rootNode`).
        XCTAssertEqual(childOptional._childrenNodes.count, 1)
        XCTAssert((childOptional._rootNode as AnyObject?) === sut)
    }

    func testInjectedTreeDescriptionPublicProperty() {
        struct Foo: Equatable {}
        let sut = SimpleParentChild.Parent()
        XCTAssertTrue(
            sut._injectedTreeDescription.contains("Parent"),
            "Expected the description to mention the scope's own type name"
        )
        sut.injectObject(Foo())
        XCTAssertTrue(sut._injectedTreeDescription.contains("💉 Foo"))
    }

    func testResolveAncestorReturnsNilForNonInjectionTreeNode() {
        // `resolveAncestor` is used by @Reducer-generated code to resolve an ancestor Store
        // from an AnyObject — when that object isn't an InjectionTreeNode at all, it must
        // return nil rather than crash.
        XCTAssertNil(resolveAncestor(SimpleParentChild.Parent.self, from: NSObject()))
    }

    // MARK: - Reassigning an already-parented value to an optional @Subscope slot

    func testReassigningAlreadyParentedOptionalSubscopeChildIsANoOp() {
        let sut = ParentChildGrandSon.Parent()
        _ = sut.child
        guard let child = sut.child else {
            XCTFail("Expected child to be created")
            return
        }
        // First read wires grandson <- child.
        let grandson = child.grandson
        XCTAssertNotNil(grandson)
        // Reassigning the SAME already-parented value back onto its own optional Subscope
        // slot exercises assignChildOnPropertyWrapperSet's isOptional-branch no-op path:
        // the value already has a parent, so it just logs and returns rather than re-wiring.
        child.grandson = grandson
        XCTAssert(child.grandson === grandson)
    }

    // MARK: - Superscope.description

    func testSuperscopeDescriptionReflectsValueTypeWhenNotOverridden() {
        let wrapper = Superscope<SimpleParentChild.Parent>()
        XCTAssertEqual(wrapper.description, "\(SimpleParentChild.Parent.self)")
    }
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
        child.injectSuperscopeForTesting(parent)
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
        parent.injectSuperscopeForTesting(injected)
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
        @Injected(InjectableStruct.self) var injectedStruct: InjectableStruct
        @Injected(InjectableClass.self) var injectedClass: InjectableClass
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

    // Was: "TODO: Protocols can't be injected, solution for now is to create protocolwitness".
    // Fixed via Injectable — a concrete type's defaultValue can return a protocol type, not just
    // Self, so a real protocol can be the injected type without any separate mechanism.
    protocol GreeterProtocol {
        var greeting: String { get }
    }
    struct RealGreeter: GreeterProtocol {
        let greeting = "real"
    }
    struct DefaultGreeter: GreeterProtocol, Injectable {
        let greeting = "default"
        static var defaultValue: GreeterProtocol { DefaultGreeter() }
    }

    final class ScopeWithProtocolInjectable: Statostore, ObservableObject {
        typealias When = Void
        @Injected(DefaultGreeter.self) var greeter: GreeterProtocol
        func update(_ when: Void) throws { }
    }

    func testInjectProtocol() {
        let sut = ScopeWithProtocolInjectable()

        // Returns the type's own declared default before injection — same shape as
        // testInjectClass/testInjectStruct above, just with a protocol-typed default.
        XCTAssertEqual(sut.greeter.greeting, "default")

        // The `for:` overload — T is pinned by DefaultGreeter's own InjectedValue, no explicit
        // upcast needed even though RealGreeter's own static type here is RealGreeter. Without
        // it, a bare injectObject(RealGreeter()) would silently register under "RealGreeter"
        // instead, and the assertion below would see "default", not "real".
        sut.injectObject(RealGreeter(), for: DefaultGreeter.self)
        XCTAssertEqual(sut.greeter.greeting, "real")
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
            @Injected(InjectableStruct.self) var injectedStruct: InjectableStruct
            @Injected(InjectableClass.self) var injectedClass: InjectableClass
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
            @Injected(InjectableStruct.self) var injectedStruct: InjectableStruct
            @Injected(InjectableClass.self) var injectedClass: InjectableClass
            static var defaultValue: Parent = Parent()
        }
        final class Child: InjectionTreeNode, Injectable, ObservableObject {
            @Superscope var parent: Parent
            @Subscope var grandson: GrandSon? = GrandSon()
            @Injected(InjectableStruct.self) var injectedStruct: InjectableStruct
            @Injected(InjectableClass.self) var injectedClass: InjectableClass
            static var defaultValue: Child = Child()
        }
        final class GrandSon: InjectionTreeNode, ObservableObject {
            @Superscope var parent: Parent
            @Superscope var child: Child
            @Injected(InjectableStruct.self) var injectedStruct: InjectableStruct
            @Injected(InjectableClass.self) var injectedClass: InjectableClass
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
// swiftlint:enable nesting
