//
//  StoreBindTests.swift
//  Statoscope
//
//  Tests for ReducerStoreProtocol.bind(_:dismissWhen:) — the reusable presentation-Binding
//  helper exposed so consumers can build their own .sheet/.popover/.navigationDestination/
//  custom presentation wrappers around build<Name>View, without reimplementing the
//  Binding(get:set:) boilerplate by hand.
//

import XCTest
import SwiftUI
@_spi(Internal) @testable import Statoscope

@Reducer
private struct BindableChildReducer {
    struct State {
        var label: String = ""
    }
    enum When {}

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {}
}

@Reducer
private struct BindableParentReducer {
    struct State {
        @SubState var child: BindableChildReducer.State?
        var alertMessage: String?
    }
    enum When {
        case showChild
        case dismissChild
        case showAlert(String)
        case dismissAlert
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .showChild:
            state.child = BindableChildReducer.State()
        case .dismissChild:
            state.child = nil
        case .showAlert(let message):
            state.alertMessage = message
        case .dismissAlert:
            state.alertMessage = nil
        }
    }
}

final class StoreBindTests: XCTestCase {

    // MARK: - State-keypath overload (public, consumer-facing)

    func testBindReadsFalseWhenOptionalStatePropertyIsNil() throws {
        let store = BindableParentReducer.Store(initialState: BindableParentReducer.State())
        let binding = store.bind(\.alertMessage, dismissWhen: .dismissAlert)
        XCTAssertFalse(binding.wrappedValue, "No alertMessage set yet — binding should read false")
    }

    func testBindReadsTrueWhenOptionalStatePropertyIsSet() throws {
        let store = BindableParentReducer.Store(initialState: BindableParentReducer.State())
        store.send(.showAlert("Something happened"))
        let binding = store.bind(\.alertMessage, dismissWhen: .dismissAlert)
        XCTAssertTrue(binding.wrappedValue, "alertMessage is set — binding should read true")
    }

    func testSettingBindingToFalseDispatchesDismissWhen() throws {
        let store = BindableParentReducer.Store(initialState: BindableParentReducer.State())
        store.send(.showAlert("Something happened"))
        XCTAssertNotNil(store.state.alertMessage)

        let binding = store.bind(\.alertMessage, dismissWhen: .dismissAlert)
        binding.wrappedValue = false

        XCTAssertNil(store.state.alertMessage, "Setting the binding to false must send dismissWhen")
    }

    func testSettingBindingToTrueHasNoEffect() throws {
        // Presentation is driven by state, not by the binding.
        let store = BindableParentReducer.Store(initialState: BindableParentReducer.State())
        let binding = store.bind(\.alertMessage, dismissWhen: .dismissAlert)

        binding.wrappedValue = true

        XCTAssertNil(store.state.alertMessage, "Setting the binding to true must not mutate state")
    }

    func testBindTracksLiveStateAcrossMultipleReads() throws {
        // The Binding's `get` closure re-reads store.state each time — it's not a snapshot
        // taken once at bind() call time.
        let store = BindableParentReducer.Store(initialState: BindableParentReducer.State())
        let binding = store.bind(\.child, dismissWhen: .dismissChild)

        XCTAssertFalse(binding.wrappedValue)
        store.send(.showChild)
        XCTAssertTrue(binding.wrappedValue, "Same Binding instance must reflect the store's current state")
        store.send(.dismissChild)
        XCTAssertFalse(binding.wrappedValue)
    }

    // MARK: - Works for a @SubState child too, not just a plain optional property

    func testBindWorksOnSubStateChildKeyPath() throws {
        let store = BindableParentReducer.Store(initialState: BindableParentReducer.State())
        store.send(.showChild)
        XCTAssertNotNil(store.children.child, "Sanity check: child store exists")

        let binding = store.bind(\.child, dismissWhen: .dismissChild)
        XCTAssertTrue(binding.wrappedValue)

        binding.wrappedValue = false
        XCTAssertNil(store.state.child)
        XCTAssertNil(store.children.child, "Dismissing via the binding must tear down the child store too")
    }

    // MARK: - Static, model/send-based overload (Reducer.bind) — for StoreViewProtocol views,
    // which only ever hold `model`/`send`, never a live store, so the instance-based overload
    // above isn't callable from them at all.

    func testStaticBindReadsFalseWhenOptionalStatePropertyIsNilInModel() throws {
        let model = BindableParentReducer.State()
        let binding = BindableParentReducer.bind(\.alertMessage, in: model, dismissWhen: .dismissAlert, send: { _ in })
        XCTAssertFalse(binding.wrappedValue)
    }

    func testStaticBindReadsTrueWhenOptionalStatePropertyIsSetInModel() throws {
        var model = BindableParentReducer.State()
        model.alertMessage = "Hello"
        let binding = BindableParentReducer.bind(\.alertMessage, in: model, dismissWhen: .dismissAlert, send: { _ in })
        XCTAssertTrue(binding.wrappedValue)
    }

    func testStaticBindSettingToFalseCallsSendWithDismissWhen() throws {
        let model = BindableParentReducer.State()
        var dispatched: [BindableParentReducer.When] = []
        let binding = BindableParentReducer.bind(\.alertMessage, in: model, dismissWhen: .dismissAlert, send: { dispatched.append($0) })

        binding.wrappedValue = false

        XCTAssertEqual(dispatched.count, 1)
        if case .dismissAlert = dispatched.first {
            // expected
        } else {
            XCTFail("Expected .dismissAlert, got \(String(describing: dispatched.first))")
        }
    }

    func testStaticBindSettingToTrueDoesNotCallSend() throws {
        let model = BindableParentReducer.State()
        var dispatched: [BindableParentReducer.When] = []
        let binding = BindableParentReducer.bind(\.alertMessage, in: model, dismissWhen: .dismissAlert, send: { dispatched.append($0) })

        binding.wrappedValue = true

        XCTAssertTrue(dispatched.isEmpty, "Setting the static binding to true must not dispatch anything")
    }

    func testStaticBindDoesNotRequireALiveStore() throws {
        // The whole point: this compiles and works with ONLY a State value and a send
        // closure — no Store<R> instance anywhere, matching what a StoreViewProtocol view
        // (model: State, send: (When) -> Void) actually has available.
        func fakeStoreViewProtocolBody(model: BindableParentReducer.State, send: @escaping (BindableParentReducer.When) -> Void) -> Bool {
            BindableParentReducer.bind(\.alertMessage, in: model, dismissWhen: .dismissAlert, send: send).wrappedValue
        }
        XCTAssertFalse(fakeStoreViewProtocolBody(model: BindableParentReducer.State()) { _ in })
    }
}
