//
//  Tutorial05_Scopes.swift
//  Statoscope
//
//  Examples from Tutorial 05: Hierarchical Scopes
//

import Foundation
import StatoscopeTesting
import Statoscope
import XCTest

/// Tutorial 05: Parent-Child Scope Composition
enum Tutorial05 {

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
        static var defaultValue = PersistenceProvider(get: { [] }, set: { _ in })
    }

    struct ArticleDTO: Codable, Equatable {
        let id: String
        let title: String
        let content: String
    }

    struct FeedListDTO: Codable, Equatable {
        let articles: [ArticleDTO]
    }

    // MARK: - Parent Scope

    final class NewsFeed: Statostore, ObservableObject {
        @Published var loadingFeatureToggles: Bool = true
        @Subscope var atList: NewsFeedList?

        enum When {
            case systemLoadedScope
            case featureTogglesLoaded(favoritesEnabled: Bool)
        }

        func update(_ when: When) throws {
            switch when {
            case .systemLoadedScope:
                loadingFeatureToggles = true
                // Simulate loading feature toggles
                effectsState.enqueue(
                    AnyEffect { true }  // Simulate favoritesEnabled = true
                        .map { When.featureTogglesLoaded(favoritesEnabled: $0) }
                )

            case .featureTogglesLoaded(let favoritesEnabled):
                loadingFeatureToggles = false
                // Create child scope with feature toggle parameter
                atList = NewsFeedList(favoritesEnabled: favoritesEnabled)
            }
        }
    }

    // MARK: - Child Scope (List)

    final class NewsFeedList: Statostore, ObservableObject {
        let favoritesEnabled: Bool

        @Published var loading: Bool = false
        @Published var loadedDTO: FeedListDTO?
        @Subscope var readingArticle: NewsFeedArticle?
        @Published var favorites: [Favorite] = []

        enum When {
            case systemLoadedScope
            case networkListDidFinish(FeedListDTO)
            case navigateFromListToChild(id: String)
            case favorite(id: String)
        }

        init(favoritesEnabled: Bool) {
            self.favoritesEnabled = favoritesEnabled
        }

        @Injected var date: DateProvider
        @Injected var persistence: PersistenceProvider

        func update(_ when: When) throws {
            switch when {
            case .systemLoadedScope:
                loading = true
                favorites = try persistence.get()
                effectsState.enqueue(
                    AnyEffect {
                        FeedListDTO(articles: [
                            ArticleDTO(id: "1", title: "Article 1", content: "Content 1"),
                            ArticleDTO(id: "2", title: "Article 2", content: "Content 2")
                        ])
                    }
                    .map(When.networkListDidFinish)
                )

            case .networkListDidFinish(let dto):
                loading = false
                loadedDTO = dto

            case .navigateFromListToChild(let id):
                // Create child article scope
                readingArticle = NewsFeedArticle(favoritesEnabled: favoritesEnabled, id: id)

            case .favorite(let id):
                guard favoritesEnabled else { return }
                if let favIndex = favorites.firstIndex(where: { $0.id == id }) {
                    favorites.remove(at: favIndex)
                } else {
                    favorites.append(Favorite(id: id, dateAdded: date.currentDate()))
                }
                try persistence.set(favorites)
            }
        }
    }

    // MARK: - Child Scope (Article Detail)

    final class NewsFeedArticle: Statostore, ObservableObject {
        let favoritesEnabled: Bool
        let id: String

        @Published var loading: Bool = false
        @Published var loadedDTO: ArticleDTO?
        @Published var favorites: [Favorite] = []

        enum When {
            case systemLoadedScope
            case networkDidFinish(ArticleDTO)
            case favorite(id: String)
        }

        init(favoritesEnabled: Bool, id: String) {
            self.favoritesEnabled = favoritesEnabled
            self.id = id
        }

        @Injected var date: DateProvider
        @Injected var persistence: PersistenceProvider

        func update(_ when: When) throws {
            switch when {
            case .systemLoadedScope:
                loading = true
                favorites = try persistence.get()
                effectsState.enqueue(
                    AnyEffect {
                        ArticleDTO(id: self.id, title: "Article \(self.id)", content: "Content for \(self.id)")
                    }
                    .map(When.networkDidFinish)
                )

            case .networkDidFinish(let dto):
                loading = false
                loadedDTO = dto

            case .favorite(let id):
                guard favoritesEnabled else { return }
                if let favIndex = favorites.firstIndex(where: { $0.id == id }) {
                    favorites.remove(at: favIndex)
                } else {
                    favorites.append(Favorite(id: id, dateAdded: date.currentDate()))
                }
                try persistence.set(favorites)
            }
        }
    }

    // MARK: - Tests

    final class ScopesTests: XCTestCase {

        func testParentCreatesChildWithParameters() throws {
            try NewsFeed.GIVEN {
                NewsFeed()
            }
            .THEN(\.loadingFeatureToggles, equals: true)
            .THEN { scope in
                XCTAssertNil(scope.atList)
            }
            .WHEN(.systemLoadedScope)
            .WHEN_OlderEffectCompletes(with: .featureTogglesLoaded(favoritesEnabled: true))
            .THEN(\.loadingFeatureToggles, equals: false)
            .THEN { scope in
                XCTAssertNotNil(scope.atList)
                XCTAssertEqual(scope.atList?.favoritesEnabled, true)
            }
            .runTest()
        }

        func testChildInheritsFeatureToggle() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)
            var savedFavorites: [Favorite] = []

            try NewsFeedList.GIVEN {
                NewsFeedList(favoritesEnabled: true)
                    .injectObject(DateProvider { fixedDate })
                    .injectObject(
                        PersistenceProvider(
                            get: { savedFavorites },
                            set: { savedFavorites = $0 }
                        )
                    )
            }
            .WHEN(.systemLoadedScope)
            .THEN(\.loading, equals: true)
            .WHEN_OlderEffectCompletes(with: .networkListDidFinish(
                FeedListDTO(articles: [
                    ArticleDTO(id: "1", title: "Article 1", content: "Content 1")
                ])
            ))
            .THEN(\.loading, equals: false)
            .WHEN(.favorite(id: "1"))
            .THEN(\.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
            .runTest()
        }

        func testFavoritesDisabledWhenToggleOff() throws {
            try NewsFeedList.GIVEN {
                NewsFeedList(favoritesEnabled: false)
                    .injectObject(DateProvider { Date(timeIntervalSince1970: 1000) })
                    .injectObject(
                        PersistenceProvider(get: { [] }, set: { _ in })
                    )
            }
            .WHEN(.favorite(id: "1"))
            .THEN(\.favorites, equals: [])  // No favorite added when disabled
            .runTest()
        }

        func testNavigationCreatesChildScope() throws {
            try NewsFeedList.GIVEN {
                NewsFeedList(favoritesEnabled: true)
            }
            .THEN { scope in
                XCTAssertNil(scope.readingArticle)
            }
            .WHEN(.navigateFromListToChild(id: "1"))
            .THEN { scope in
                XCTAssertNotNil(scope.readingArticle)
                XCTAssertEqual(scope.readingArticle?.id, "1")
                XCTAssertEqual(scope.readingArticle?.favoritesEnabled, true)
            }
            .runTest()
        }
    }
}
