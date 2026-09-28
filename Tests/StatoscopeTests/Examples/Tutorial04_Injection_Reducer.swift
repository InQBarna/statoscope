//
//  Tutorial04_Injection_Reducer.swift
//  Statoscope
//
//  Examples from Tutorial 04: Dependency Injection (Reducer Pattern)
//

import Foundation
import StatoscopeTesting
@_spi(Internal) @testable import Statoscope
import XCTest

/// Tutorial 04: Dependency Injection with Injectable protocol (Reducer Pattern)
enum Tutorial04Reducer {

    // MARK: - Dependencies

    // @extract:begin Injection-Reducer-DateProvider-01
    struct DateProvider: Injectable {
        var currentDate: () -> Date
        static var defaultValue = DateProvider(currentDate: Date.init)
    }
    // @extract:end Injection-Reducer-DateProvider-01

    // @extract:begin Injection-Reducer-PersistenceProvider-01
    struct Favorite: Codable, Equatable {
        let id: String
        let dateAdded: Date
    }

    struct PersistenceProvider: Injectable {
        let get: () throws -> [Favorite]
        let set: ([Favorite]) throws -> Void

        static var defaultValue = PersistenceProvider(
            get: {
                guard let data = UserDefaults.standard.data(forKey: "favorites") else {
                    return []
                }
                return try JSONDecoder().decode([Favorite].self, from: data)
            },
            set: { favorites in
                let data = try JSONEncoder().encode(favorites)
                UserDefaults.standard.set(data, forKey: "favorites")
            }
        )
    }
    // @extract:end Injection-Reducer-PersistenceProvider-01

    // @extract:begin Injection-Reducer-NetworkProvider-01
    // A real Swift protocol, not an Injectable struct-of-closures: NetworkProvider has more than
    // one plausible conformance (the real network call, a fake for tests), which is exactly what
    // protocol-typed injection is for. DateProvider/PersistenceProvider above are Injectable
    // because they only ever have ONE real shape; NetworkProvider doesn't.
    protocol NetworkProvider {
        func fetchArticles() async throws -> [ArticleDTO]
    }

    // RealNetworkProvider also conforms to Injectable itself — needed the moment NetworkProvider
    // is read declaratively (@ReducerInjected, below in Tutorial04b_ReducerInjected.swift) rather
    // than imperatively via dependencies.resolve(): a declarative property wrapper must never
    // throw, so it needs a default to fall back to. Declaring defaultValue with a protocol return
    // type instead of Self is all that's needed — no separate mechanism. dependencies.resolve()
    // below still won't consult it — it's for the OTHER section.
    struct RealNetworkProvider: NetworkProvider, Injectable {
        static var defaultValue: NetworkProvider { RealNetworkProvider() }

        func fetchArticles() async throws -> [ArticleDTO] {
            let url = URL(string: "https://api.example.com/articles")!
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode([ArticleDTO].self, from: data)
        }
    }

    struct ArticleDTO: Codable, Equatable {
        let id: String
        let title: String
        let content: String
    }
    // @extract:end Injection-Reducer-NetworkProvider-01

    // MARK: - Reducer

    // @extract:begin Injection-Reducer-Reducer-01
    @Reducer
    struct NewsFeedListReducer {
        struct State {
            var loading: Bool = false
            var loadedArticles: [ArticleDTO]?
            var favorites: [Favorite] = []
        }

        enum When {
            case systemLoadedScope
            case networkDidFinish([ArticleDTO])
            case favorite(id: String)
        }

        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .systemLoadedScope:
                let persistence: PersistenceProvider = try dependencies.resolve()
                let network: NetworkProvider = try dependencies.resolve()

                state.loading = true
                state.loadedArticles = nil
                state.favorites = try persistence.get()
                effectsState.enqueue(
                    AnyEffect {
                        try await network.fetchArticles()
                    }
                    .map(When.networkDidFinish)
                )

            case .networkDidFinish(let articles):
                state.loading = false
                state.loadedArticles = articles

            case .favorite(let id):
                let date: DateProvider = try dependencies.resolve()
                let persistence: PersistenceProvider = try dependencies.resolve()

                if let favIndex = state.favorites.firstIndex(where: { $0.id == id }) {
                    // Remove from favorites
                    state.favorites.remove(at: favIndex)
                } else {
                    // Add to favorites
                    state.favorites.append(Favorite(id: id, dateAdded: date.currentDate()))
                }
                try persistence.set(state.favorites)
            }
        }
    }
    // @extract:end Injection-Reducer-Reducer-01

    // MARK: - Real app setup

    // @extract:begin Injection-Reducer-RealSetup-01
    // `dependencies.resolve()` never falls back to `Injectable.defaultValue` automatically —
    // unlike `@Injected`/`@ReducerInjected`, a miss always throws. So even DateProvider and
    // PersistenceProvider, despite being `Injectable`, need to be injected explicitly once —
    // typically right here, wherever your app creates this Store for real use (a SwiftUI
    // `@StateObject`, your composition root, etc.), not just inside tests.
    static func makeNewsFeedStore() -> NewsFeedListReducer.Store {
        NewsFeedListReducer.Store(initialState: NewsFeedListReducer.State())
            .injectObject(DateProvider.defaultValue)
            .injectObject(PersistenceProvider.defaultValue)
            .injectObject(RealNetworkProvider.defaultValue)
    }
    // @extract:end Injection-Reducer-RealSetup-01

    // MARK: - Tests

    final class InjectionTests: XCTestCase {

        // @extract:begin Injection-Reducer-Test-01
        func testDependencyInjection() throws {
            // A fake conformance, not a reconfigured RealNetworkProvider — protocol-typed
            // dependencies get swapped by providing a different conforming type, unlike
            // DateProvider/PersistenceProvider above (same concrete struct, different closures).
            struct FakeNetworkProvider: NetworkProvider {
                let articles: [ArticleDTO]
                func fetchArticles() async throws -> [ArticleDTO] { articles }
            }

            let fixedDate = Date(timeIntervalSince1970: 1000)
            var savedFavorites: [Favorite] = []

            try NewsFeedListReducer.Store.GIVEN {
                NewsFeedListReducer.Store(initialState: NewsFeedListReducer.State())
                    .injectObject(DateProvider { fixedDate })
                    .injectObject(
                        PersistenceProvider(
                            get: { savedFavorites },
                            set: { savedFavorites = $0 }
                        )
                    )
                    .injectObject(
                        // The "for:" overload pins T to NetworkProvider via the key's own type —
                        // no explicit upcast needed, and no way to get it wrong.
                        FakeNetworkProvider(articles: [
                            ArticleDTO(id: "1", title: "Article 1", content: "Content 1"),
                            ArticleDTO(id: "2", title: "Article 2", content: "Content 2")
                        ]),
                        for: RealNetworkProvider.self
                    )
            }
            .WHEN(.systemLoadedScope)
            .THEN(\.state.loading, equals: true)
            .THEN(\.state.favorites, equals: [])
            .WHEN_OlderEffectCompletes(with: .networkDidFinish([
                ArticleDTO(id: "1", title: "Article 1", content: "Content 1"),
                ArticleDTO(id: "2", title: "Article 2", content: "Content 2")
            ]))
            .THEN(\.state.loading, equals: false)
            .THEN { scope in
                XCTAssertEqual(scope.state.loadedArticles?.count, 2)
            }
            .WHEN(.favorite(id: "1"))
            .THEN(\.state.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
            .THEN { _ in
                XCTAssertEqual(savedFavorites, [Favorite(id: "1", dateAdded: fixedDate)])
            }
            .runTest()
        }
        // @extract:end Injection-Reducer-Test-01

        func testRealStoreCanBeCreatedWithRealDependencies() {
            // Never sends an event, so this never actually hits the network or UserDefaults —
            // just proves the composition-root function above wires up a store that starts in a
            // sane state, without needing dependencies.resolve() to throw.
            let store = Tutorial04Reducer.makeNewsFeedStore()
            XCTAssertEqual(store.state.loading, false)
            XCTAssertEqual(store.state.favorites, [])
        }

        func testToggleFavorite() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)
            var savedFavorites: [Favorite] = []

            try NewsFeedListReducer.Store.GIVEN {
                NewsFeedListReducer.Store(initialState: NewsFeedListReducer.State())
                    .injectObject(DateProvider { fixedDate })
                    .injectObject(
                        PersistenceProvider(
                            get: { savedFavorites },
                            set: { savedFavorites = $0 }
                        )
                    )
            }
            // Add favorite
            .WHEN(.favorite(id: "1"))
            .THEN(\.state.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
            // Remove favorite
            .WHEN(.favorite(id: "1"))
            .THEN(\.state.favorites, equals: [])
            .WHEN(.favorite(id: "1"))
            .THEN(\.state.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
            .runTest()
            
            XCTAssertEqual(savedFavorites, [Favorite(id: "1", dateAdded: fixedDate)])
        }
    }
}
