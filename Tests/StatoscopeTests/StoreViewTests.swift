//
//  StoreViewTests.swift
//  Statoscope
//
//  Covers Sources/Statoscope/SwiftUI/StoreView.swift — previously entirely uncovered. None of
//  the tested surface depends on SwiftUI's render engine: StoreView's init and the
//  StoreViewProtocol binding helpers are plain closure/property wiring, checkable by
//  constructing values and reading their stored properties or Binding.wrappedValue directly,
//  the same approach StoreBindTests.swift and SwiftUIBindingsTests.swift already use. Only
//  `StoreView.body` itself (a one-line passthrough) is left untested, since exercising it needs
//  an actual view-rendering host and it carries no logic of its own.
//

import Foundation
import XCTest
import SwiftUI
@testable import Statoscope

private final class ViewableScope: Statostore, ObservableObject {
    typealias When = Int
    @Published var count: Int = 0
    var lastReceived: Int?
    func update(_ when: Int) throws {
        lastReceived = when
        count = when
    }
}

private struct PassthroughView: View {
    let text: String
    var body: some View { Text(text) }
}

final class StoreViewTests: XCTestCase {

    // MARK: - StoreView.init

    func testStoreViewWiresScopeAndState() {
        let scope = ViewableScope()
        let storeView = StoreView(scope: scope) { state, _ in
            PassthroughView(text: "\(state.count)")
        }
        XCTAssertTrue(storeView.scope === scope)
        XCTAssertTrue(storeView.state === scope)
    }

    func testStoreViewBuilderSendClosureDispatchesToScope() {
        let scope = ViewableScope()
        var capturedSend: ((Int) -> Void)?
        _ = StoreView(scope: scope) { _, send in
            capturedSend = send
            return PassthroughView(text: "x")
        }
        capturedSend?(7)
        XCTAssertEqual(scope.lastReceived, 7)
    }

    // MARK: - StoreProtocol.buildStoreView(view:)

    func testBuildStoreViewWithClosureWiresScope() {
        let scope = ViewableScope()
        let storeView = scope.buildStoreView { state, _ in
            PassthroughView(text: "\(state.count)")
        }
        XCTAssertTrue(storeView.scope === scope)
    }

    // MARK: - StoreProtocol.buildStoreView(_:) — StoreViewProtocol-typed overload

    private struct FakeStoreView: StoreViewProtocol {
        let model: ViewableScope
        let send: (Int) -> Void
        init(model: ViewableScope, send: @escaping (Int) -> Void) {
            self.model = model
            self.send = send
        }
        var body: some View { Text("\(model.count)") }
    }

    func testBuildStoreViewWithProtocolTypeWiresModelAndSend() {
        let scope = ViewableScope()
        scope.count = 3
        let storeView = scope.buildStoreView(FakeStoreView.self)
        XCTAssertTrue(storeView.view.model === scope)
        storeView.view.send(9)
        XCTAssertEqual(scope.lastReceived, 9)
    }

    // MARK: - StoreViewProtocol binding helpers

    private struct BindableModel {
        var flag: Bool
        var optionalValue: Int?
    }
    private enum BindableWhen: Equatable {
        case setFlag(Bool)
        case setOptional(Int?)
    }
    private struct BindableStoreView: StoreViewProtocol {
        let model: BindableModel
        let send: (BindableWhen) -> Void
        init(model: BindableModel, send: @escaping (BindableWhen) -> Void) {
            self.model = model
            self.send = send
        }
        var body: some View { EmptyView() }
    }

    func testBindConstantReadsFixedValueAndSetCallsWhen() {
        var received: BindableWhen?
        let view = BindableStoreView(model: BindableModel(flag: false), send: { received = $0 })
        let binding = view.bind(constant: 5) { .setOptional($0) }
        XCTAssertEqual(binding.wrappedValue, 5)
        binding.wrappedValue = 6
        XCTAssertEqual(received, .setOptional(6))
    }

    func testBindKeyPathReadsFromModel() {
        let view = BindableStoreView(model: BindableModel(flag: true, optionalValue: 2), send: { _ in })
        let binding = view.bind(\.flag) { .setFlag($0) }
        XCTAssertTrue(binding.wrappedValue)
    }

    func testBindKeyPathSetCallsWhenAndSend() {
        var received: BindableWhen?
        let view = BindableStoreView(model: BindableModel(flag: false), send: { received = $0 })
        let binding = view.bind(\.flag) { .setFlag($0) }
        binding.wrappedValue = true
        XCTAssertEqual(received, .setFlag(true))
    }

    func testWeakBindReadsFromModelAndDispatchesOnSet() {
        var received: BindableWhen?
        let view = BindableStoreView(model: BindableModel(flag: false, optionalValue: 4), send: { received = $0 })
        let binding = view.weakBind(\.optionalValue) { .setOptional($0) }
        XCTAssertEqual(binding.wrappedValue, 4)
        binding.wrappedValue = 8
        XCTAssertEqual(received, .setOptional(8))
    }

    func testBindGetterClosureReadsAndDispatchesOnSet() {
        var received: BindableWhen?
        let view = BindableStoreView(model: BindableModel(flag: false, optionalValue: 1), send: { received = $0 })
        let binding = view.bind({ $0.model.optionalValue.map { $0 * 10 } }, { .setOptional($0) })
        XCTAssertEqual(binding.wrappedValue, 10)
        binding.wrappedValue = 99
        XCTAssertEqual(received, .setOptional(99))
    }

    func testBindIsPresentedWithoutWhenReadsButIgnoresSet() {
        let view = BindableStoreView(model: BindableModel(flag: false, optionalValue: 1), send: { _ in XCTFail("must not send") })
        let binding = view.bindIsPresented(\.optionalValue)
        XCTAssertTrue(binding.wrappedValue)
        binding.wrappedValue = false
    }

    func testBindIsPresentedWithWhenReadsAndDispatchesOnSet() {
        var received: BindableWhen?
        let view = BindableStoreView(model: BindableModel(flag: false), send: { received = $0 })
        let binding = view.bindIsPresented(\.optionalValue) { .setFlag($0) }
        XCTAssertFalse(binding.wrappedValue)
        binding.wrappedValue = true
        XCTAssertEqual(received, .setFlag(true))
    }
}
