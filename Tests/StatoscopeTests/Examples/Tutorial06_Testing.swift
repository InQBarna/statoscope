//
//  Tutorial06_Testing.swift
//  Statoscope
//
//  Examples from Tutorial 06: Testing Patterns
//

import Foundation
import StatoscopeTesting
import Statoscope
import XCTest

/// Tutorial 06: Comprehensive Testing Patterns
enum Tutorial06 {

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
    }

    // MARK: - Child Scope

    final class NewsFeedArticle: Statostore, ObservableObject {
        let id: String

        @Published var loading: Bool = false
        @Published var loadedTitle: String?
        @Published var isFavorite: Bool = false

        enum When {
            case systemLoadedScope
            case articleLoaded(title: String)
            case favorite
        }

        init(id: String) {
            self.id = id
        }

        func update(_ when: When) throws {
            switch when {
            case .systemLoadedScope:
                loading = true
                effectsState.enqueue(
                    AnyEffect { "Article \(self.id)" }
                        .map(When.articleLoaded)
                )
            case .articleLoaded(let title):
                loading = false
                loadedTitle = title
            case .favorite:
                isFavorite.toggle()
            }
        }
    }

    // MARK: - Parent Scope

    final class NewsFeed: Statostore, ObservableObject {
        @Published var loading: Bool = false
        @Published var loadedArticles: [ArticleDTO]?
        @Subscope var readingArticle: NewsFeedArticle?
        @Published var favorites: [Favorite] = []

        enum When {
            case systemLoadedScope
            case networkDidFinish([ArticleDTO])
            case navigateToChild(id: String)
            case favorite(id: String)
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
                        [
                            ArticleDTO(id: "1", title: "Article 1"),
                            ArticleDTO(id: "2", title: "Article 2")
                        ]
                    }
                    .map(When.networkDidFinish)
                )

            case .networkDidFinish(let articles):
                loading = false
                loadedArticles = articles

            case .navigateToChild(let id):
                readingArticle = NewsFeedArticle(id: id)

            case .favorite(let id):
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

    final class TestingPatternsTests: XCTestCase {

        /// Test demonstrates GIVEN/WHEN/THEN pattern with mocked dependencies
        func testBasicGivenWhenThenPattern() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)

            try NewsFeed.GIVEN {
                NewsFeed()
                    .injectObject(DateProvider { fixedDate })
                    .injectObject(PersistenceProvider(get: { [] }, set: { _ in }))
            }
            .THEN(\.loading, equals: false)
            .THEN(\.favorites, equals: [])
            .WHEN(.systemLoadedScope)
            .THEN(\.loading, equals: true)
            .runTest(assertNoPendingEffects: false)  // Effect enqueued but not completed
        }

        /// Test demonstrates effect completion verification
        func testEffectCompletion() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)
            let expectedArticles = [
                ArticleDTO(id: "1", title: "Article 1"),
                ArticleDTO(id: "2", title: "Article 2")
            ]

            try NewsFeed.GIVEN {
                NewsFeed()
                    .injectObject(DateProvider { fixedDate })
                    .injectObject(PersistenceProvider(get: { [] }, set: { _ in }))
            }
            .WHEN(.systemLoadedScope)
            .THEN(\.loading, equals: true)
            .WHEN_OlderEffectCompletes(with: .networkDidFinish(expectedArticles))
            .THEN(\.loading, equals: false)
            .THEN(\.loadedArticles, equals: expectedArticles)
            .runTest()
        }

        /// Test demonstrates navigation creates a child scope
        func testNavigationCreatesChildScope() throws {
            try NewsFeed.GIVEN {
                NewsFeed()
            }
            .THEN { scope in
                XCTAssertNil(scope.readingArticle)
            }
            .WHEN(.navigateToChild(id: "1"))
            .THEN { scope in
                XCTAssertNotNil(scope.readingArticle)
                XCTAssertEqual(scope.readingArticle?.id, "1")
            }
            .WHEN(.navigateToChild(id: "2"))
            .THEN { scope in
                XCTAssertEqual(scope.readingArticle?.id, "2")
            }
            .runTest()
        }

        /// Test demonstrates WITH for sending events to and asserting on a child scope
        func testChildScopeInteractionsWithWITH() throws {
            try NewsFeed.GIVEN {
                NewsFeed()
            }
            .WHEN(.navigateToChild(id: "42"))
            // Drop into the child scope — all subsequent steps operate on NewsFeedArticle
            .WITH(\.readingArticle)
            .THEN { article in
                XCTAssertEqual(article.id, "42")
                XCTAssertFalse(article.isFavorite)
            }
            .WHEN(.systemLoadedScope)
            .THEN(\.loading, equals: true)
            .WHEN_OlderEffectCompletes(with: .articleLoaded(title: "Article 42"))
            .THEN(\.loading, equals: false)
            .THEN(\.loadedTitle, equals: "Article 42")
            .WHEN(.favorite)
            .THEN(\.isFavorite, equals: true)
            .WHEN(.favorite)
            .THEN(\.isFavorite, equals: false)  // Toggles back
            // POP back to the parent to continue asserting on NewsFeed
            .POP()
            .runTest()
        }
        
        /// Test demonstrates WHEN for sending events to and asserting on a child scope
        func testChildScopeInteractionsWithSubscopesKeypaths() throws {
            try NewsFeed.GIVEN {
                NewsFeed()
            }
            .WHEN(.navigateToChild(id: "42"))
            // Drop into the child scope — all subsequent steps operate on NewsFeedArticle
            .THEN(\.readingArticle?.id, equals: "42")
            .THEN(\.readingArticle?.isFavorite, equals: false)
            .WHEN(\.readingArticle, .systemLoadedScope)
            .THEN(\.readingArticle?.loading, equals: true)
            // .WHEN_OlderEffectCompletes(with: .articleLoaded(title: "Article 42"))
            .runTest(assertNoPendingEffects: false)
        }

        /// Test demonstrates custom closure assertions
        func testCustomAssertions() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)

            try NewsFeed.GIVEN {
                NewsFeed()
                    .injectObject(DateProvider { fixedDate })
                    .injectObject(PersistenceProvider(get: { [] }, set: { _ in }))
            }
            .WHEN(.favorite(id: "1"))
            .THEN { scope in
                XCTAssertEqual(scope.favorites.count, 1)
                XCTAssertEqual(scope.favorites.first?.id, "1")
                XCTAssertEqual(scope.favorites.first?.dateAdded, fixedDate)
            }
            .runTest()
        }

        /// Test demonstrates dependency injection verification
        func testDependencyInjection() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)
            var persistedFavorites: [Favorite] = []

            try NewsFeed.GIVEN {
                NewsFeed()
                    .injectObject(DateProvider { fixedDate })
                    .injectObject(
                        PersistenceProvider(
                            get: { persistedFavorites },
                            set: { persistedFavorites = $0 }
                        )
                    )
            }
            .WHEN(.favorite(id: "1"))
            .THEN(\.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
            .THEN { _ in
                // Verify persistence was called
                XCTAssertEqual(persistedFavorites.count, 1)
                XCTAssertEqual(persistedFavorites.first?.id, "1")
            }
            .runTest()
        }

        /// Test demonstrates testing state transitions
        func testStateTransitions() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)

            try NewsFeed.GIVEN {
                NewsFeed()
                    .injectObject(DateProvider { fixedDate })
                    .injectObject(PersistenceProvider(get: { [] }, set: { _ in }))
            }
            // Initial state
            .THEN(\.favorites, equals: [])
            // Add favorite
            .WHEN(.favorite(id: "1"))
            .THEN(\.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
            // Add another
            .WHEN(.favorite(id: "2"))
            .THEN { scope in
                XCTAssertEqual(scope.favorites.count, 2)
            }
            // Remove first
            .WHEN(.favorite(id: "1"))
            .THEN(\.favorites, equals: [Favorite(id: "2", dateAdded: fixedDate)])
            .runTest()
        }

        /// Test demonstrates acceptance criteria as code
        func testFeatureUserCanSaveArticleAsFavorite() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)

            try NewsFeed.GIVEN {
                NewsFeed()
                    .injectObject(DateProvider { fixedDate })
                    .injectObject(PersistenceProvider(get: { [] }, set: { _ in }))
            }
            .WHEN(.systemLoadedScope)
            .THEN(\.loading, equals: true)
            .WHEN_OlderEffectCompletes(with: .networkDidFinish([
                ArticleDTO(id: "1", title: "Article 1"),
                ArticleDTO(id: "2", title: "Article 2")
            ]))
            .THEN(\.loading, equals: false)
            .WHEN(.navigateToChild(id: "1"))
            .THEN { scope in
                XCTAssertEqual(scope.readingArticle?.id, "1")
            }
            .WHEN(.favorite(id: "1"))
            .THEN(\.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
            .runTest()
        }
    }
}
