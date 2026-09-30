//
//  EffectClassConformanceTests.swift
//  Statoscope
//
//  Effect._injectNode's default implementation (Sources/Statoscope/Effects/InjectedForEffect.swift)
//  walks up Mirror.superclassMirror to the ultimate ancestor before scanning for
//  @InjectedForEffect-wrapped properties — logic that only matters for a class-conforming Effect,
//  since every Effect in this codebase (and everything @EffectStruct generates) is a struct, which
//  has no superclassMirror at all. Never tested with an actual class before. This is a hand-written
//  class Effect (not @EffectStruct-generated, which only ever produces structs), proving the
//  pattern is real, working, supported API — not dead code.
//

import Foundation
import Statoscope
import XCTest

protocol StampProviderProtocol {
    var stamp: String { get }
}

struct RealStampProvider: StampProviderProtocol, Injectable {
    let stamp: String = "real"
    static var defaultValue: StampProviderProtocol { RealStampProvider() }
}

struct MockStampProvider: StampProviderProtocol {
    let stamp: String = "mock"
}

final class ClassBasedStampEffect: Effect {
    @InjectedForEffect(RealStampProvider.self) var provider: StampProviderProtocol

    func runEffect() async throws -> String {
        provider.stamp
    }
}

private final class ClassEffectScope: Statostore, ObservableObject {
    enum When {
        case start
        case completed(String)
    }

    @Published var result: String?

    func update(_ when: When) throws {
        switch when {
        case .start:
            effectsState.enqueue(ClassBasedStampEffect().map(When.completed))
        case .completed(let value):
            result = value
        }
    }
}

final class EffectClassConformanceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        scopeEffectsDisabledInUnitTests = false
    }

    override func tearDown() {
        scopeEffectsDisabledInUnitTests = true
        super.tearDown()
    }

    func testClassBasedEffectUsesDefaultProviderWhenNothingInjected() async throws {
        let scope = ClassEffectScope()
        scope.send(.start)

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(scope.result, "real")
    }

    func testClassBasedEffectResolvesInjectedProviderFromTree() async throws {
        let scope = ClassEffectScope()
            .injectObject(MockStampProvider(), for: RealStampProvider.self)
        scope.send(.start)

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(scope.result, "mock")
    }
}
