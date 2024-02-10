//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 10/2/24.
//

import Foundation
import XCTest
@testable import Statoscope

        // currentSnapshot = newSnapshot
class EffectsHanlderImplementationTests: XCTestCase {
    
    override func setUp() async throws {
        // StatoscopeLogger.logEnabled = true
        scopeEffectsDisabledInUnitTests = false
    }
    
    override class func tearDown() {
        // StatoscopeLogger.logEnabled = false
        scopeEffectsDisabledInUnitTests = true
    }
    
    static var firstEffectMilliseconds: UInt64 = 100
    static var secondEffectMilliseconds: UInt64 = 500
    
    private struct WaitMillisecondsEffect: Effect, Equatable {
        let milliseconds: UInt64
        func runEffect() async throws {
            try await Task.sleep(nanoseconds: milliseconds * 1000_000)
        }
    }
    
    private struct AutoCancelledEffect: Effect, Equatable {
        let milliseconds: UInt64
        func runEffect() async throws {
            try await Task.sleep(nanoseconds: milliseconds * 1000_000)
            throw CancellationError()
        }
    }
    
    func testEnqueueEmptySnapshot() throws {
        let exp = expectation(description: "Wait for new snapshot")
        exp.isInverted = true
        let sut: EffectsHandlerImplementation<Void> =
            EffectsHandlerImplementation(logPrefix: #function)
        let currentSnapshot = sut.buildSnapshot()
        XCTAssert(currentSnapshot.enquedEffects.isEmpty)
        XCTAssert(currentSnapshot.snapshotEffects.isEmpty)
        XCTAssert(currentSnapshot.cancelledEffects.isEmpty)
        XCTAssert(currentSnapshot.effects.isEmpty)
        XCTAssert(currentSnapshot.currentRequestedEffects.isEmpty)
        let newState = try sut.runEnqueuedEffectAndGetWhenResults(newSnapshot: currentSnapshot) 
        { completedEffect, when, newState in
            exp.fulfill()
        }
        let newStateEffects = newState.map { $0.1 }
        XCTAssert(newStateEffects.isEmpty)
        _ = XCTWaiter.wait(for: [exp], timeout: 1.0)
    }
    
    func testEnqueueOneEffect() throws {
        let exp = expectation(description: "Wait for new snapshot")
        let sut: EffectsHandlerImplementation<Void> =
            EffectsHandlerImplementation(logPrefix: #function)
        var currentSnapshot = sut.buildSnapshot()
        let effect = WaitMillisecondsEffect(milliseconds: Self.firstEffectMilliseconds)
        currentSnapshot.enqueue(effect)
        let newState = try sut.runEnqueuedEffectAndGetWhenResults(newSnapshot: currentSnapshot)
        { completedEffect, when, newState in
            XCTAssertEqual(completedEffect.pristine as? WaitMillisecondsEffect, effect)
            let newStateEffects = newState.map { $0.1 }
            XCTAssert(newStateEffects.isEmpty)
            exp.fulfill()
        }
        let newStateEffects = newState.map { $0.1 }
        XCTAssertEqual(newStateEffects.count, 1)
        XCTAssertEqual(newStateEffects.first?.pristine as? WaitMillisecondsEffect, effect)
        _ = XCTWaiter.wait(for: [exp], timeout: 5.0)
    }
    
    func testEnqueueTwoEffect() throws {
        let exp = expectation(description: "Wait for new snapshot")
        exp.expectedFulfillmentCount = 2
        let sut: EffectsHandlerImplementation<Void> =
            EffectsHandlerImplementation(logPrefix: #function)
        var currentSnapshot = sut.buildSnapshot()
        let effect1 = WaitMillisecondsEffect(milliseconds: Self.firstEffectMilliseconds)
        let effect2 = WaitMillisecondsEffect(milliseconds: Self.secondEffectMilliseconds)
        currentSnapshot.enqueue(effect1)
        currentSnapshot.enqueue(effect2)
        var receivedStates: [[AnyEffect<Void>]] = []
        let newState = try sut.runEnqueuedEffectAndGetWhenResults(newSnapshot: currentSnapshot)
        { completedEffect, when, newState in
            let newStateEffects = newState.map { $0.1 }
            receivedStates.append(newStateEffects)
            exp.fulfill()
        }
        let newStateEffects = newState.map { $0.1 }
        XCTAssertEqual(newStateEffects.count, 2)
        XCTAssertEqual(newStateEffects.first?.pristine as? WaitMillisecondsEffect, effect1)
        XCTAssertEqual(newStateEffects.last?.pristine as? WaitMillisecondsEffect, effect2)
        _ = XCTWaiter.wait(for: [exp], timeout: 5.0)
        
        XCTAssertEqual(receivedStates.count, 2)
        
        let firstReceivedState = try XCTUnwrap(receivedStates.first)
        XCTAssertEqual(firstReceivedState.count, 1)
        XCTAssertEqual(firstReceivedState.first?.pristine as? WaitMillisecondsEffect, effect2)
        
        let secondReceivedState = try XCTUnwrap(receivedStates.last)
        XCTAssert(secondReceivedState.isEmpty)
    }
    
    func testEnqueueAutocancelledEffect() throws {
        let exp = expectation(description: "Wait for new snapshot")
        let sut: EffectsHandlerImplementation<Void> =
        EffectsHandlerImplementation(logPrefix: #function)
        
        // Enqueue an effect
        var currentSnapshot = sut.buildSnapshot()
        let effect = AutoCancelledEffect(milliseconds: Self.firstEffectMilliseconds)
        currentSnapshot.enqueue(effect)
        let newState = try sut.runEnqueuedEffectAndGetWhenResults(newSnapshot: currentSnapshot)
        { completedEffect, when, newState in
            XCTAssertEqual(completedEffect.pristine as? AutoCancelledEffect, effect)
            let newStateEffects = newState.map { $0.1 }
            XCTAssert(newStateEffects.isEmpty)
            exp.fulfill()
        }
        let newStateEffects = newState.map { $0.1 }
        XCTAssertEqual(newStateEffects.count, 1)
        _ = XCTWaiter.wait(for: [exp], timeout: 1.0)
    }
    func testEnqueueAndCancelOneEffect() throws {
        let exp = expectation(description: "Wait for new snapshot")
        let sut: EffectsHandlerImplementation<Void> =
        EffectsHandlerImplementation(logPrefix: #function)
        
        // Enqueue an effect
        var currentSnapshot = sut.buildSnapshot()
        let effect = WaitMillisecondsEffect(milliseconds: Self.firstEffectMilliseconds)
        currentSnapshot.enqueue(effect)
        let newState = try sut.runEnqueuedEffectAndGetWhenResults(newSnapshot: currentSnapshot)
        { completedEffect, when, newState in
            XCTAssertEqual(completedEffect.pristine as? WaitMillisecondsEffect, effect)
            let newStateEffects = newState.map { $0.1 }
            XCTAssert(newStateEffects.isEmpty)
            exp.fulfill()
        }
        let newStateEffects = newState.map { $0.1 }
        XCTAssertEqual(newStateEffects.count, 1)
        
        // Cancel the effect
        let exp2 = expectation(description: "This completion won't be called")
        exp2.isInverted = true
        var currentSnapshot2 = sut.buildSnapshot()
        currentSnapshot2.cancelAllEffects()
        let newState2 = try sut.runEnqueuedEffectAndGetWhenResults(newSnapshot: currentSnapshot2)
        { completedEffect, when, newState in
            exp2.fulfill()
        }
        XCTAssertEqual(newState2.map({ $0.1 }).count, 0)
        _ = XCTWaiter.wait(for: [exp, exp2], timeout: 1.0)
    }
}
