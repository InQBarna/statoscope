//
//  InjectionStoreTests.swift
//  
//
//  Created by Sergi Hernanz on 23/2/24.
//

import Foundation
@testable import Statoscope
import StatoscopeTesting
import XCTest

@available(iOS 16.0, *)
final class InjectionStoreTests: XCTestCase {

    func testRegisterResolveObject() throws {
        class InjectableObject {
            let param: String
            init(param: String) {
                self.param = param
            }
        }
        let injected = InjectableObject(param: "Injected")
        let sut = InjectionStore()
        sut.register(injected)
        let resolved: InjectableObject = try sut.resolve()
        XCTAssert(injected === resolved)
    }

    func testRegisterResolveObjectSecondOverwritesFirst() throws {
        class InjectableObject {
            let param: String
            init(param: String) {
                self.param = param
            }
        }
        let injected = InjectableObject(param: "Injected")
        let injectedSecond = InjectableObject(param: "Injected second")
        let sut = InjectionStore()
        sut.register(injected)
        let resolved: InjectableObject = try sut.resolve()
        XCTAssert(injected === resolved)
        sut.register(injectedSecond)
        let resolvedSecond: InjectableObject = try sut.resolve()
        XCTAssert(injectedSecond === resolvedSecond)
    }

    func testResolveThrows() throws {
        class InjectableObject {
            let param: String
            init(param: String) {
                self.param = param
            }
        }
        let sut = InjectionStore()
        XCTAssertThrowsError(try sut.resolve() as InjectableObject)
    }

    func testResolveThrowingError() throws {
        class InjectableObject {
            let param: String
            init(param: String) {
                self.param = param
            }
        }
        let sut = InjectionStore()
        do {
            _ = try sut.resolve() as InjectableObject
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "No injected value found: \"InjectableObject\"")
        }
    }

    func testTreeDescription() throws {
        class MyInjectableObject: CustomStringConvertible {
            let param: String
            init(param: String) {
                self.param = param
            }
            var description: String {
                return "MyInjectableObject(\(param))"
            }
        }
        let injected = MyInjectableObject(param: "Injected")
        let sut = InjectionStore()
        sut.register(injected)
        let treeDescription = sut.treeDescription
        let expectedDescription = [
            "💉 MyInjectableObject:\tMyInjectableObject(Injected)"
        ]
        XCTAssertEqual(treeDescription, expectedDescription)

        struct InjectableStruct: Equatable {
            let param: String
        }
        let injectedStruct = InjectableStruct(param: "Injected")
        sut.registerValue(injectedStruct)
        try XCTAssertEqualDiff(
            sut.treeDescription,
            """
            💉 MyInjectableObject:\tMyInjectableObject(Injected)
            💉 InjectableStruct
            """
                .split(separator: String.newLine)
                .map { String($0) }
        )
    }

    func testRegisterResolveValue() throws {
        struct InjectableStruct: Equatable {
            let param: String
        }
        let injected = InjectableStruct(param: "Injected")
        let sut = InjectionStore()
        sut.registerValue(injected)
        let resolved: InjectableStruct = try sut.resolve()
        XCTAssertEqual(injected, resolved)
    }

    func testRegisterResolveValueSecondOverwritesFirst() throws {
        struct InjectableStruct: Equatable {
            let param: String
        }
        let injected = InjectableStruct(param: "Injected")
        let sut = InjectionStore()
        sut.registerValue(injected)
        let resolved: InjectableStruct = try sut.resolve()
        XCTAssertEqual(injected, resolved)
        let injectedSecond = InjectableStruct(param: "InjectedSecond")
        sut.registerValue(injectedSecond)
        let resolvedSecond: InjectableStruct = try sut.resolve()
        XCTAssertEqual(injectedSecond, resolvedSecond)
    }

    // MARK: - Protocol-typed injection (registerValue keyed by T, not type(of: dependency))

    private protocol NetworkServiceProtocol {
        var name: String { get }
    }
    private struct RealNetworkService: NetworkServiceProtocol {
        let name = "real"
    }
    private struct MockNetworkService: NetworkServiceProtocol {
        let name = "mock"
    }

    func testRegisterValueResolvesByProtocolTypeWhenInjectedAsThatProtocol() throws {
        let sut = InjectionStore()
        // Explicit upcast — T is inferred as NetworkServiceProtocol at this call site. Passes
        // regardless of the T.self-vs-type(of:) fix below — inside a generic function body they
        // already agree for an existential-typed T. Kept as a baseline/regression test for the
        // ergonomics injectObject's own doc describes, not as proof of that specific fix.
        sut.registerValue(RealNetworkService() as NetworkServiceProtocol)
        let resolved: NetworkServiceProtocol = try sut.resolve()
        XCTAssertEqual(resolved.name, "real")
    }

    func testRegisterValueWithoutUpcastIsNotFoundByProtocolType() throws {
        let sut = InjectionStore()
        // No upcast — T is inferred as RealNetworkService, registered under that concrete key.
        sut.registerValue(RealNetworkService())
        // A later resolve by the protocol type must NOT find it — documents the gotcha directly,
        // rather than just asserting the fix works in the happy path.
        XCTAssertThrowsError(try sut.resolve() as NetworkServiceProtocol)
        // The concrete type still resolves fine — nothing about the fix changes this.
        let resolvedConcrete: RealNetworkService = try sut.resolve()
        XCTAssertEqual(resolvedConcrete.name, "real")
    }

    // MARK: - registerValue keyed by T, not type(of:) — the REAL bug this fixes: class subtyping,
    // not protocols. Confirmed empirically (see InjectionStore.swift's own comment): inside a
    // generic function, type(of:) on a value whose static type is a GENERIC PARAMETER follows
    // normal class polymorphism (dynamic subclass), unlike protocol existentials (which agree with
    // T.self). So injecting a subclass instance under its base class type used to register under
    // the SUBCLASS's name, not the base class — exactly the scenario a test double needs.

    private class AnimalBase {
        var sound: String { "..." }
    }
    private class RealDog: AnimalBase {
        override var sound: String { "woof" }
    }
    private class MockAnimal: AnimalBase {
        override var sound: String { "mock-sound" }
    }

    func testRegisterResolvesByBaseClassWhenInjectedAsABaseClass() throws {
        let sut = InjectionStore()
        let dog = RealDog()
        sut.register(dog as AnimalBase)
        let resolved: AnimalBase = try sut.resolve()
        XCTAssertEqual(resolved.sound, "woof")
        XCTAssert(resolved === dog)
    }

    func testRegisterValueResolvesByBaseClassWhenInjectedAsABaseClass() throws {
        let sut = InjectionStore()
        // The upcast is the whole point: inject a SUBCLASS instance, typed as the BASE class.
        sut.registerValue(RealDog() as AnimalBase)
        let resolved: AnimalBase = try sut.resolve()
        XCTAssertEqual(resolved.sound, "woof")
    }

    func testRegisterValueSwapsBaseClassRegistrationForTesting() throws {
        let sut = InjectionStore()
        sut.registerValue(RealDog() as AnimalBase)
        XCTAssertEqual((try sut.resolve() as AnimalBase).sound, "woof")
        // Same key ("AnimalBase") — overwrites, same as every other "second overwrites first" test.
        sut.registerValue(MockAnimal() as AnimalBase)
        XCTAssertEqual((try sut.resolve() as AnimalBase).sound, "mock-sound")
    }

    // NOTE: register<T: AnyObject> (weak class injection) can't take this same fix further —
    // `sut.register(RealNetworkServiceObject() as NetworkServiceObjectProtocol)` fails to compile:
    // "instance method 'register' requires that 'any NetworkServiceObjectProtocol' be a class
    // type." Swift's `T: AnyObject` generic constraint does not accept an existential of a
    // class-constrained protocol (`any P` where `P: AnyObject`), even though the underlying
    // instance genuinely is a class — a separate, deeper Swift generics/existential limitation
    // from the string-keying bug fixed above, discovered while testing this fix, not solved by
    // it. registerValue (the struct/value path — the actual motivating scenario) is unaffected.
    // Left as an open follow-up, not fixed on this branch.

    func testSwappingProtocolTypedRegistrationForTesting() throws {
        let sut = InjectionStore()
        sut.registerValue(RealNetworkService() as NetworkServiceProtocol)
        XCTAssertEqual((try sut.resolve() as NetworkServiceProtocol).name, "real")
        // Same key ("NetworkServiceProtocol") — overwrites, exactly like the existing
        // second-overwrites-first tests above, just with a protocol-typed key this time.
        sut.registerValue(MockNetworkService() as NetworkServiceProtocol)
        XCTAssertEqual((try sut.resolve() as NetworkServiceProtocol).name, "mock")
    }
}
