//
//  Tutorial06_Testing_Reducer.swift
//  Statoscope
//
//  Examples from Tutorial 06: Testing Patterns (Reducer Pattern)
//

import Foundation
import StatoscopeTesting
@_spi(Internal) @testable import Statoscope
import XCTest

/// Tutorial 06: Comprehensive Testing Patterns (Reducer Pattern)
enum Tutorial06Reducer {

    // MARK: - Dependencies

    // @extract:begin Testing-Reducer-Dependencies-01
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
    // @extract:end Testing-Reducer-Dependencies-01

    // MARK: - Child Reducer

    // @extract:begin Testing-Reducer-ChildReducer-01
    @Reducer
    struct NewsFeedArticleReducer {
        struct State {
            var id: String = ""
            var loading: Bool = false
            var loadedTitle: String?
            var isFavorite: Bool = false
        }

        enum When {
            case systemLoadedScope
            case articleLoaded(title: String)
            case favorite
        }

        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            let articleId = state.id
            switch when {
            case .systemLoadedScope:
                state.loading = true
                effectsState.enqueue(
                    AnyEffect { "Article \(articleId)" }
                        .map(When.articleLoaded)
                )
            case .articleLoaded(let title):
                state.loading = false
                state.loadedTitle = title
            case .favorite:
                state.isFavorite.toggle()
            }
        }
    }
    // @extract:end Testing-Reducer-ChildReducer-01

    // MARK: - Parent Reducer

    // @extract:begin Testing-Reducer-ParentReducer-01
    @Reducer
    struct NewsFeedReducer {
        struct State {
            var loading: Bool = false
            var loadedArticles: [ArticleDTO]?
            @SubState var readingArticle: NewsFeedArticleReducer.State?
            var favorites: [Favorite] = []
        }

        enum When {
            case systemLoadedScope
            case networkDidFinish([ArticleDTO])
            case navigateToChild(id: String)
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
                state.loading = true
                state.favorites = try persistence.get()
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
                state.loading = false
                state.loadedArticles = articles

            case .navigateToChild(let id):
                var articleState = NewsFeedArticleReducer.State()
                articleState.id = id
                state.readingArticle = articleState

            case .favorite(let id):
                let date: DateProvider = try dependencies.resolve()
                let persistence: PersistenceProvider = try dependencies.resolve()
                if let favIndex = state.favorites.firstIndex(where: { $0.id == id }) {
                    state.favorites.remove(at: favIndex)
                } else {
                    state.favorites.append(Favorite(id: id, dateAdded: date.currentDate()))
                }
                try persistence.set(state.favorites)
            }
        }
    }
    // @extract:end Testing-Reducer-ParentReducer-01

    // MARK: - Tests

    final class TestingPatternsTests: XCTestCase {

        /// Test demonstrates GIVEN/WHEN/THEN pattern with mocked dependencies
        // @extract:begin Testing-Reducer-BasicFlow-01
        func testBasicGivenWhenThenPattern() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)

            try NewsFeedReducer.Store.GIVEN(
                state: NewsFeedReducer.State()
            ) { $0
                .injectObject(DateProvider { fixedDate })
                .injectObject(PersistenceProvider(get: { [] }, set: { _ in }))
            }
            .THEN(\.state.loading, equals: false)
            .THEN(\.state.favorites, equals: [])
            .WHEN(.systemLoadedScope)
            .THEN(\.state.loading, equals: true)
            .runTest(assertNoPendingEffects: false)  // Effect enqueued but not completed
        }
        // @extract:end Testing-Reducer-BasicFlow-01

        /// Test demonstrates effect completion verification
        // @extract:begin Testing-Reducer-EffectCompletion-01
        func testEffectCompletion() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)
            let expectedArticles = [
                ArticleDTO(id: "1", title: "Article 1"),
                ArticleDTO(id: "2", title: "Article 2")
            ]

            try NewsFeedReducer.Store.GIVEN(
                state: NewsFeedReducer.State()
            ) { $0
                .injectObject(DateProvider { fixedDate })
                .injectObject(PersistenceProvider(get: { [] }, set: { _ in }))
            }
            .WHEN(.systemLoadedScope)
            .THEN(\.state.loading, equals: true)
            .WHEN_OlderEffectCompletes(with: .networkDidFinish(expectedArticles))
            .THEN(\.state.loading, equals: false)
            .THEN(\.state.loadedArticles, equals: expectedArticles)
            .runTest()
        }
        // @extract:end Testing-Reducer-EffectCompletion-01

        /// Test demonstrates navigation creates a child store
        // @extract:begin Testing-Reducer-Navigation-01
        func testNavigationCreatesChildStore() throws {
            try NewsFeedReducer.Store.GIVEN(
                state: NewsFeedReducer.State()
            )
            .THEN { store in
                XCTAssertNil(store.children.readingArticle)
            }
            .WHEN(.navigateToChild(id: "1"))
            .THEN { store in
                XCTAssertNotNil(store.children.readingArticle)
                XCTAssertEqual(store.children.readingArticle?.state.id, "1")
            }
            .WHEN(.navigateToChild(id: "2"))
            .THEN { store in
                XCTAssertEqual(store.children.readingArticle?.state.id, "2")
            }
            .runTest()
        }
        // @extract:end Testing-Reducer-Navigation-01

        /// Test demonstrates WITH for sending events to and asserting on a child store
        // @extract:begin Testing-Reducer-WITH-01
        func testChildStoreInteractionsWithWITH() throws {
            try NewsFeedReducer.Store.GIVEN(
                state: NewsFeedReducer.State()
            )
            .WHEN(.navigateToChild(id: "42"))
            // Drop into the child store — all subsequent steps operate on Store<NewsFeedArticleReducer>
            .WITH(\.children.readingArticle)
            .THEN { articleStore in
                XCTAssertEqual(articleStore.state.id, "42")
                XCTAssertFalse(articleStore.state.isFavorite)
            }
            .WHEN(.systemLoadedScope)
            .THEN(\.state.loading, equals: true)
            .WHEN_OlderEffectCompletes(with: .articleLoaded(title: "Article 42"))
            .THEN(\.state.loading, equals: false)
            .THEN(\.state.loadedTitle, equals: "Article 42")
            .WHEN(.favorite)
            .THEN(\.state.isFavorite, equals: true)
            .WHEN(.favorite)
            .THEN(\.state.isFavorite, equals: false)  // Toggles back
            // POP back to the parent store to continue asserting on NewsFeedReducer
            .POP()
            .runTest()
        }
        // @extract:end Testing-Reducer-WITH-01

        /// Test demonstrates keypath-based event sending and state assertion on a child store
        ///
        /// Reducer difference vs Statostore:
        ///   Non-Reducer: .THEN(\.readingArticle?.id, equals: "42")
        ///   Reducer:     .THEN(\.children.readingArticle?.state.id, equals: "42")
        ///
        ///   Non-Reducer: .WHEN(\.readingArticle, .systemLoadedScope)
        ///   Reducer:     .WHEN(\.children.readingArticle, .systemLoadedScope)
        // @extract:begin Testing-Reducer-Keypaths-01
        func testChildStoreInteractionsWithSubscopeKeypaths() throws {
            try NewsFeedReducer.Store.GIVEN(
                state: NewsFeedReducer.State()
            )
            .WHEN(.navigateToChild(id: "42"))
            // Keypath assertions into child store state via \.children.readingArticle?.state.*
            .THEN(\.children.readingArticle?.state.id, equals: "42")
            .THEN(\.children.readingArticle?.state.isFavorite, equals: false)
            // Send an event to the child store via its keypath — same API as non-Reducer
            .WHEN(\.children.readingArticle, .systemLoadedScope)
            .THEN(\.children.readingArticle?.state.loading, equals: true)
            // WHEN_OlderEffectCompletes cannot reach child store effects from the parent plan.
            // The child's effect lives in Store<NewsFeedArticleReducer>.effectsState, not the parent's.
            // Use WITH to descend into the child plan where WHEN_OlderEffectCompletes works:
            //   .WITH(\.children.readingArticle)
            //   .WHEN_OlderEffectCompletes(with: .articleLoaded(title: "Article 42"))
            //   .POP()
            .runTest(assertNoPendingEffects: false)
        }
        // @extract:end Testing-Reducer-Keypaths-01

        /// Test demonstrates custom closure assertions
        // @extract:begin Testing-Reducer-CustomAssertions-01
        func testCustomAssertions() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)

            try NewsFeedReducer.Store.GIVEN(
                state: NewsFeedReducer.State()
            ) { $0
                    .injectObject(DateProvider { fixedDate })
                    .injectObject(PersistenceProvider(get: { [] }, set: { _ in }))
            }
            .WHEN(.favorite(id: "1"))
            .THEN { store in
                XCTAssertEqual(store.state.favorites.count, 1)
                XCTAssertEqual(store.state.favorites.first?.id, "1")
                XCTAssertEqual(store.state.favorites.first?.dateAdded, fixedDate)
            }
            .runTest()
        }
        // @extract:end Testing-Reducer-CustomAssertions-01

        /// Test demonstrates dependency injection verification
        // @extract:begin Testing-Reducer-DependencyInjection-01
        func testDependencyInjection() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)
            var persistedFavorites: [Favorite] = []

            try NewsFeedReducer.Store.GIVEN(
                state: NewsFeedReducer.State()
            ) { $0
                    .injectObject(DateProvider { fixedDate })
                    .injectObject(
                        PersistenceProvider(
                            get: { persistedFavorites },
                            set: { persistedFavorites = $0 }
                        )
                    )
            }
            .WHEN(.favorite(id: "1"))
            .THEN(\.state.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
            .THEN { _ in
                XCTAssertEqual(persistedFavorites.count, 1)
                XCTAssertEqual(persistedFavorites.first?.id, "1")
            }
            .runTest()
        }
        // @extract:end Testing-Reducer-DependencyInjection-01

        /// Test demonstrates testing state transitions
        // @extract:begin Testing-Reducer-StateTransitions-01
        func testStateTransitions() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)

            try NewsFeedReducer.Store.GIVEN(
                state: NewsFeedReducer.State()
            ) { $0
                    .injectObject(DateProvider { fixedDate })
                    .injectObject(PersistenceProvider(get: { [] }, set: { _ in }))
            }
            // Initial state
            .THEN(\.state.favorites, equals: [])
            // Add favorite
            .WHEN(.favorite(id: "1"))
            .THEN(\.state.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
            // Add another
            .WHEN(.favorite(id: "2"))
            .THEN { store in
                XCTAssertEqual(store.state.favorites.count, 2)
            }
            // Remove first
            .WHEN(.favorite(id: "1"))
            .THEN(\.state.favorites, equals: [Favorite(id: "2", dateAdded: fixedDate)])
            .runTest()
        }
        // @extract:end Testing-Reducer-StateTransitions-01

        /// Test demonstrates acceptance criteria as code
        // @extract:begin Testing-Reducer-Capstone-01
        func testFeatureUserCanSaveArticleAsFavorite() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)

            try NewsFeedReducer.Store.GIVEN(
                state: NewsFeedReducer.State()
            ) { $0
                .injectObject(DateProvider { fixedDate })
                .injectObject(PersistenceProvider(get: { [] }, set: { _ in }))
            }
            .WHEN(.systemLoadedScope)
            .THEN(\.state.loading, equals: true)
            .WHEN_OlderEffectCompletes(with: .networkDidFinish([
                ArticleDTO(id: "1", title: "Article 1"),
                ArticleDTO(id: "2", title: "Article 2")
            ]))
            .THEN(\.state.loading, equals: false)
            .WHEN(.navigateToChild(id: "1"))
            .THEN { store in
                XCTAssertEqual(store.children.readingArticle?.state.id, "1")
            }
            .WHEN(.favorite(id: "1"))
            .THEN(\.state.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
            .runTest()
        }
        // @extract:end Testing-Reducer-Capstone-01
    }
}
