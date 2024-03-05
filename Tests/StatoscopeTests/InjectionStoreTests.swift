//
//  InjectionStoreTests.swift
//  
//
//  Created by Sergi Hernanz on 23/2/24.
//

import Foundation
@testable import Statoscope
import XCTest

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

    func testTreeDescription() {
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
            "+ MyInjectableObject:\tMyInjectableObject(Injected)"
        ]
        XCTAssertEqual(treeDescription, expectedDescription)

        struct InjectableStruct: Equatable {
            let param: String
        }
        let injectedStruct = InjectableStruct(param: "Injected")
        sut.registerValue(injectedStruct)
        let expectedDescriptionSecond = [
            "+ MyInjectableObject:\tMyInjectableObject(Injected)",
            "+++ InjectableStruct"
        ]
        XCTAssertEqual(sut.treeDescription, expectedDescriptionSecond)
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
}
