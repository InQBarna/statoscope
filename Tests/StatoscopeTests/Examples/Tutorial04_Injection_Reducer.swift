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

    struct DateProvider: Injectable {
        var currentDate: () -> Date
        static var defaultValue = DateProvider(currentDate: Date.init)
    }

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

    struct NetworkProvider: Injectable {
        let fetchArticles: () async throws -> [ArticleDTO]

        static var defaultValue = NetworkProvider(
            fetchArticles: {
                let url = URL(string: "https://api.example.com/articles")!
                let (data, _) = try await URLSession.shared.data(from: url)
                return try JSONDecoder().decode([ArticleDTO].self, from: data)
            }
        )
    }

    struct ArticleDTO: Codable, Equatable {
        let id: String
        let title: String
        let content: String
    }

    // MARK: - Reducer

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

    // MARK: - Tests

    final class InjectionTests: XCTestCase {

        func testDependencyInjection() throws {
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
                        NetworkProvider(
                            fetchArticles: {
                                [
                                    ArticleDTO(id: "1", title: "Article 1", content: "Content 1"),
                                    ArticleDTO(id: "2", title: "Article 2", content: "Content 2")
                                ]
                            }
                        )
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
