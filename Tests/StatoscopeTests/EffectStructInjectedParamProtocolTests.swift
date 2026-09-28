//
//  EffectStructInjectedParamProtocolTests.swift
//  Statoscope
//
//  @InjectedParam with a genuine Swift protocol (not just an Injectable value type), for
//  @EffectStruct parameters. Runtime end-to-end coverage (real effect execution, real injection
//  tree) — Tests/StatoscopeMacrosTests/EffectStructTests.swift only asserts macro EXPANSION,
//  never runs the generated code.
//

import Foundation
import Statoscope
import XCTest

protocol GreetingServiceProtocol {
    func greet(name: String) -> String
}

// RealGreetingService conforms to Injectable itself — declares its default with a protocol return
// type instead of Self, discoverable through the type's own name.
struct RealGreetingService: GreetingServiceProtocol, Injectable {
    func greet(name: String) -> String { "Hello, \(name)!" }
    static var defaultValue: GreetingServiceProtocol { RealGreetingService() }
}

struct MockGreetingService: GreetingServiceProtocol {
    func greet(name: String) -> String { "Mocked greeting for \(name)" }
}

enum GreetingEffectNamespace {
    @EffectStruct
    static func buildGreeting(
        name: String,
        @InjectedParam(RealGreetingService.self) service: GreetingServiceProtocol
    ) async throws -> String {
        service.greet(name: name)
    }
}

final class GreeterScope: Statostore, ObservableObject {
    enum When {
        case load(String)
        case loaded(String)
    }

    @Published var greeting: String?

    func update(_ when: When) throws {
        switch when {
        case .load(let name):
            effectsState.enqueue(
                GreetingEffectNamespace.BuildGreetingEffect(name: name)
                    .map(When.loaded)
            )
        case .loaded(let text):
            greeting = text
        }
    }
}

final class EffectStructInjectedParamProtocolTests: XCTestCase {

    override func setUp() {
        super.setUp()
        scopeEffectsDisabledInUnitTests = false
    }

    override func tearDown() {
        scopeEffectsDisabledInUnitTests = true
        super.tearDown()
    }

    func testDefaultServiceIsUsedWhenNothingInjected() async throws {
        let scope = GreeterScope()
        scope.send(.load("World"))

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(scope.greeting, "Hello, World!")
    }

    func testInjectedServiceIsUsedWhenPresentInTheTree() async throws {
        let scope = GreeterScope()
            .injectObject(MockGreetingService(), for: RealGreetingService.self)

        scope.send(.load("World"))

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(scope.greeting, "Mocked greeting for World")
    }
}
