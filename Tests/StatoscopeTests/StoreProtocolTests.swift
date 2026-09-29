//
//  StoreProtocolTests.swift
//  Statoscope
//
//  Direct coverage for `Statostore.set(_:_:)` (Sources/Statoscope/Statostore.swift) and
//  `StoreProtocol.sendUnsafe(_:)` (Sources/Statoscope/StoreProtocol.swift). Neither has a
//  dedicated test elsewhere: existing Statostore-based tests exercise `send(_:)` and the
//  GIVEN/WHEN/THEN test plan (which itself calls `_unsafeSendImplementation` directly, bypassing
//  the public `sendUnsafe(_:)` entry point), but never these two small, public, user-facing APIs
//  themselves.
//

import Foundation
import XCTest
@testable import Statoscope

private final class CounterStore: Statostore {
    var count: Int = 0

    enum When {
        case increment
        case fail
    }

    struct ForcedError: Error, Equatable { }

    func update(_ when: When) throws {
        switch when {
        case .increment:
            count += 1
        case .fail:
            throw ForcedError()
        }
    }
}

final class StatostoreSetTests: XCTestCase {

    func testSetMutatesPropertyThroughKeyPathAndReturnsSelfForChaining() {
        let scope = CounterStore()
        let result = scope.set(\.count, 5)
        XCTAssertTrue(result === scope)
        XCTAssertEqual(scope.count, 5)
    }
}

final class StoreProtocolSendUnsafeTests: XCTestCase {

    func testSendUnsafeAppliesUpdateAndReturnsSelfForChaining() throws {
        let scope = CounterStore()
        let result = try scope.sendUnsafe(.increment)
        XCTAssertTrue(result === scope)
        XCTAssertEqual(scope.count, 1)
    }

    func testSendUnsafePropagatesErrorsThrownFromUpdate() {
        let scope = CounterStore()
        XCTAssertThrowsError(try scope.sendUnsafe(.fail)) { error in
            XCTAssertEqual(error as? CounterStore.ForcedError, CounterStore.ForcedError())
        }
    }
}

/// `EffectfullImplementation.effectsState`'s SETTER lazily creates the associated-object storage
/// itself (mirroring the getter) for the case where a scope's `effectsState` is assigned before
/// it has ever been read. In normal operation the getter always runs first (e.g. the
/// `assert(effectsState.enquedEffects.count == 0)` at the top of `_unsafeSendImplementation`), so
/// this branch is otherwise never exercised.
final class EffectsStateSetterBeforeGetterTests: XCTestCase {

    func testAssigningEffectsStateBeforeEverReadingItInitializesStorage() {
        let scope = CounterStore()
        scope.effectsState = EffectsState(snapshotEffects: [])
        XCTAssertEqual(scope.effectsState.currentRequestedEffects.count, 0)
    }
}
