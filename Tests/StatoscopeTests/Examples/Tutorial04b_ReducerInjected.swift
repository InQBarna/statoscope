//  Tutorial04b_ReducerInjected.swift
//  Statoscope
//
//  Examples: @ReducerInjected — declarative dependency injection on Reducer.State
//
//  Demonstrates the difference between:
//    - Old: call `try dependencies.resolve()` inside each handler (Tutorial04_Injection_Reducer.swift)
//    - New: declare `@ReducerInjected(Dep.self) var dep: Dep` once on State; access as `state.dep`
//
//  Reuses NewsFeedListReducer's own dependencies rather than a separate example — DateProvider
//  (an Injectable value type) and NetworkProvider (a protocol) — to show @ReducerInjected works
//  identically for either shape, and that the protocol case needs nothing beyond
//  RealNetworkProvider's existing Injectable conformance.
//

import Foundation
import StatoscopeTesting
@_spi(Internal) @testable import Statoscope
import XCTest

extension Tutorial04Reducer {

    // MARK: - Declarative access to both dependency shapes

    /// Compare with NewsFeedListReducer, where each handler calls `try dependencies.resolve()`
    /// imperatively — here both dependencies are declared once on State and read anywhere,
    /// including outside update(). @ReducerInjected doesn't care whether a type's `defaultValue`
    /// returns Self (DateProvider) or a protocol (NetworkProvider, via RealNetworkProvider) — the
    /// declaration site looks identical either way, and neither one can ever throw.
    // @extract:begin Injection-Reducer-ReducerInjected-01
    @Reducer
    struct NewsFeedStatusReducer {
        struct State {
            @ReducerInjected(DateProvider.self) var date: DateProvider
            @ReducerInjected(RealNetworkProvider.self) var network: NetworkProvider

            var lastCheckedAt: Date?
        }

        enum When {
            case checkNow
        }

        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .checkNow:
                state.lastCheckedAt = state.date.currentDate()
            }
        }
    }
    // @extract:end Injection-Reducer-ReducerInjected-01

    // MARK: - Tests

    final class NewsFeedStatusReducerTests: XCTestCase {

        // MARK: Default values — no injection required, for either dependency shape

        // @extract:begin Injection-Reducer-DefaultTest-01
        func testDefaultValuesUsedWhenNoInjection() throws {
            // No .injectObject() at all — DateProvider.defaultValue and
            // RealNetworkProvider.defaultValue are used automatically. Neither throws, unlike
            // dependencies.resolve() in NewsFeedListReducer.
            let store = NewsFeedStatusReducer.Store(initialState: .init())

            XCTAssertTrue(store.state.network is RealNetworkProvider)

            store.send(.checkNow)
            XCTAssertNotNil(store.state.lastCheckedAt)
        }
        // @extract:end Injection-Reducer-DefaultTest-01

        // MARK: Injected values are used instead, for either dependency shape

        // @extract:begin Injection-Reducer-InjectedTest-01
        func testInjectedValuesAreUsedWhenPresent() throws {
            struct FakeNetworkProvider: NetworkProvider {
                func fetchArticles() async throws -> [ArticleDTO] { [] }
            }
            let fixedDate = Date(timeIntervalSince1970: 1000)

            let store = NewsFeedStatusReducer.Store(initialState: .init())
                .injectObject(DateProvider { fixedDate })
                .injectObject(FakeNetworkProvider(), for: RealNetworkProvider.self)

            store.send(.checkNow)

            XCTAssertEqual(store.state.lastCheckedAt, fixedDate)
            XCTAssertTrue(store.state.network is FakeNetworkProvider)
        }
        // @extract:end Injection-Reducer-InjectedTest-01
    }
}
