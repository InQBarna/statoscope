//
//  Tutorial04_Injection.swift
//  Statoscope
//
//  Examples from Tutorial 04: Dependency Injection
//

import Foundation
import StatoscopeTesting
import Statoscope
import XCTest

/// Tutorial 04: Dependency Injection with Injectable protocol
enum Tutorial04 {

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

    // MARK: - Scope

    final class NewsFeedList: Statostore, ObservableObject {
        @Published var loading: Bool = false
        @Published var loadedArticles: [ArticleDTO]?
        @Published var favorites: [Favorite] = []

        enum When {
            case systemLoadedScope
            case networkDidFinish([ArticleDTO])
            case favorite(id: String)
        }

        @Injected var date: DateProvider
        @Injected var persistence: PersistenceProvider
        @Injected var network: NetworkProvider

        func update(_ when: When) throws {
            switch when {
            case .systemLoadedScope:
                loading = true
                loadedArticles = nil
                favorites = try persistence.get()
                effectsState.enqueue(
                    AnyEffect {
                        try await self.network.fetchArticles()
                    }
                    .map(When.networkDidFinish)
                )

            case .networkDidFinish(let articles):
                loading = false
                loadedArticles = articles

            case .favorite(let id):
                if let favIndex = favorites.firstIndex(where: { $0.id == id }) {
                    // Remove from favorites
                    favorites.remove(at: favIndex)
                } else {
                    // Add to favorites
                    favorites.append(Favorite(id: id, dateAdded: date.currentDate()))
                }
                try persistence.set(favorites)
            }
        }
    }

    // MARK: - Tests

    final class InjectionTests: XCTestCase {

        func testDependencyInjection() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)
            var savedFavorites: [Favorite] = []

            try NewsFeedList.GIVEN {
                NewsFeedList()
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
            .THEN(\.loading, equals: true)
            .THEN(\.favorites, equals: [])
            .WHEN_OlderEffectCompletes(with: .networkDidFinish([
                ArticleDTO(id: "1", title: "Article 1", content: "Content 1"),
                ArticleDTO(id: "2", title: "Article 2", content: "Content 2")
            ]))
            .THEN(\.loading, equals: false)
            .THEN { scope in
                XCTAssertEqual(scope.loadedArticles?.count, 2)
            }
            .WHEN(.favorite(id: "1"))
            .THEN(\.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
            .THEN { _ in
                XCTAssertEqual(savedFavorites, [Favorite(id: "1", dateAdded: fixedDate)])
            }
            .runTest()
        }

        func testToggleFavorite() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)
            var savedFavorites: [Favorite] = []

            try NewsFeedList.GIVEN {
                NewsFeedList()
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
            .THEN(\.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
            // Remove favorite
            .WHEN(.favorite(id: "1"))
            .THEN(\.favorites, equals: [])
            .runTest()
        }
    }
}
