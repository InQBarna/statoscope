//
//  Tutorial05_Scopes_Reducer.swift
//  Statoscope
//
//  Examples from Tutorial 05: Hierarchical Scopes (Reducer Pattern)
//

import Foundation
import StatoscopeTesting
@_spi(Internal) @testable import Statoscope
import XCTest

/// Tutorial 05: Parent-Child Scope Composition (Reducer Pattern)
enum Tutorial05Reducer {

    // MARK: - Dependencies

    // @extract:begin Scopes-Reducer-Dependencies-01
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
    // @extract:end Scopes-Reducer-Dependencies-01

    // MARK: - Parent Reducer

    // @extract:begin Scopes-Reducer-NewsFeed-01
    // @extract:begin Scopes-Reducer-NewsFeed-02
    @Reducer
    struct NewsFeedReducer {
        struct State: Injectable {
            static var defaultValue: State { State() }
            var loadingFeatureToggles: Bool = true
            @SubState var atList: NewsFeedListReducer.State?
        }

        enum When {
            case systemLoadedScope
            case featureTogglesLoaded(favoritesEnabled: Bool)
        }
        // @extract:end Scopes-Reducer-NewsFeed-01

        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .systemLoadedScope:
                state.loadingFeatureToggles = true
                // Simulate loading feature toggles
                effectsState.enqueue(
                    AnyEffect { true }  // Simulate favoritesEnabled = true
                        .map { When.featureTogglesLoaded(favoritesEnabled: $0) }
                )

            case .featureTogglesLoaded(let favoritesEnabled):
                state.loadingFeatureToggles = false
                // Create child scope with feature toggle parameter
                var listState = NewsFeedListReducer.State()
                listState.favoritesEnabled = favoritesEnabled
                state.atList = listState
            }
        }
    }
    // @extract:end Scopes-Reducer-NewsFeed-02

    // MARK: - Child Reducer (List)

    // @extract:begin Scopes-Reducer-NewsFeedList-01
    // @extract:begin Scopes-Reducer-NewsFeedList-02
    @Reducer
    struct NewsFeedListReducer {
        struct State: Injectable {
            static var defaultValue: State { State() }
            var favoritesEnabled: Bool = false
            var loading: Bool = false
            var loadedDTO: FeedListDTO?
            @SubState var readingArticle: NewsFeedArticleReducer.State?
            var favorites: [Favorite] = []
        }

        enum When {
            case systemLoadedScope
            case networkListDidFinish(FeedListDTO)
            case navigateFromListToChild(id: String)
            case favorite(id: String)
        }
        // @extract:end Scopes-Reducer-NewsFeedList-01

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
                        FeedListDTO(articles: [
                            ArticleDTO(id: "1", title: "Article 1", content: "Content 1"),
                            ArticleDTO(id: "2", title: "Article 2", content: "Content 2")
                        ])
                    }
                    .map(When.networkListDidFinish)
                )

            case .networkListDidFinish(let dto):
                state.loading = false
                state.loadedDTO = dto

            case .navigateFromListToChild(let id):
                // Create child article scope
                var articleState = NewsFeedArticleReducer.State()
                articleState.favoritesEnabled = state.favoritesEnabled
                articleState.id = id
                state.readingArticle = articleState

            case .favorite(let id):
                guard state.favoritesEnabled else { return }

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
    // @extract:end Scopes-Reducer-NewsFeedList-02

    // MARK: - Child Reducer (Article Detail)

    // @extract:begin Scopes-Reducer-NewsFeedArticle-01
    // @extract:begin Scopes-Reducer-NewsFeedArticle-02
    @Reducer
    struct NewsFeedArticleReducer {
        struct State: Injectable {
            static var defaultValue: State { State() }
            var favoritesEnabled: Bool = false
            var id: String = ""
            var loading: Bool = false
            var loadedDTO: ArticleDTO?
            var favorites: [Favorite] = []
        }

        enum When {
            case systemLoadedScope
            case networkDidFinish(ArticleDTO)
            case favorite(id: String)
        }
        // @extract:end Scopes-Reducer-NewsFeedArticle-01

        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .systemLoadedScope:
                let persistence: PersistenceProvider = try dependencies.resolve()
                let articleId = state.id  // Copy to avoid capturing inout parameter

                state.loading = true
                state.favorites = try persistence.get()
                effectsState.enqueue(
                    AnyEffect {
                        ArticleDTO(id: articleId, title: "Article \(articleId)", content: "Content for \(articleId)")
                    }
                    .map(When.networkDidFinish)
                )

            case .networkDidFinish(let dto):
                state.loading = false
                state.loadedDTO = dto

            case .favorite(let id):
                guard state.favoritesEnabled else { return }

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
    // @extract:end Scopes-Reducer-NewsFeedArticle-02

    // MARK: - Tests

    final class ScopesTests: XCTestCase {

        // @extract:begin Scopes-Reducer-Tests-01
        func testParentCreatesChildWithParameters() throws {
            try NewsFeedReducer.Store.GIVEN {
                NewsFeedReducer.Store(initialState: NewsFeedReducer.State())
            }
            .THEN(\.state.loadingFeatureToggles, equals: true)
            .THEN { scope in
                XCTAssertNil(scope.state.atList)
            }
            .WHEN(.systemLoadedScope)
            .WHEN_OlderEffectCompletes(with: .featureTogglesLoaded(favoritesEnabled: true))
            .THEN(\.state.loadingFeatureToggles, equals: false)
            .THEN { scope in
                XCTAssertNotNil(scope.state.atList)
                XCTAssertEqual(scope.state.atList?.favoritesEnabled, true)
            }
            .runTest()
        }
        // @extract:end Scopes-Reducer-Tests-01

        func testChildInheritsFeatureToggle() throws {
            let fixedDate = Date(timeIntervalSince1970: 1000)
            var savedFavorites: [Favorite] = []

            var initialState = NewsFeedListReducer.State()
            initialState.favoritesEnabled = true

            try NewsFeedListReducer.Store.GIVEN {
                NewsFeedListReducer.Store(initialState: initialState)
                    .injectObject(DateProvider { fixedDate })
                    .injectObject(
                        PersistenceProvider(
                            get: { savedFavorites },
                            set: { savedFavorites = $0 }
                        )
                    )
            }
            .WHEN(.systemLoadedScope)
            .THEN(\.state.loading, equals: true)
            .WHEN_OlderEffectCompletes(with: .networkListDidFinish(
                FeedListDTO(articles: [
                    ArticleDTO(id: "1", title: "Article 1", content: "Content 1")
                ])
            ))
            .THEN(\.state.loading, equals: false)
            .WHEN(.favorite(id: "1"))
            .THEN(\.state.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
            .runTest()
        }

        func testFavoritesDisabledWhenToggleOff() throws {
            var initialState = NewsFeedListReducer.State()
            initialState.favoritesEnabled = false

            try NewsFeedListReducer.Store.GIVEN {
                NewsFeedListReducer.Store(initialState: initialState)
                    .injectObject(DateProvider { Date(timeIntervalSince1970: 1000) })
                    .injectObject(
                        PersistenceProvider(get: { [] }, set: { _ in })
                    )
            }
            .WHEN(.favorite(id: "1"))
            .THEN(\.state.favorites, equals: [])  // No favorite added when disabled
            .runTest()
        }

        // @extract:begin Scopes-Reducer-Tests-02
        func testNavigationCreatesChildScope() throws {
            var initialState = NewsFeedListReducer.State()
            initialState.favoritesEnabled = true

            try NewsFeedListReducer.Store.GIVEN {
                NewsFeedListReducer.Store(initialState: initialState)
            }
            .THEN { scope in
                XCTAssertNil(scope.state.readingArticle)
            }
            .WHEN(.navigateFromListToChild(id: "1"))
            .THEN { scope in
                XCTAssertNotNil(scope.state.readingArticle)
                XCTAssertEqual(scope.state.readingArticle?.id, "1")
                XCTAssertEqual(scope.state.readingArticle?.favoritesEnabled, true)
            }
            .runTest()
        }
        // @extract:end Scopes-Reducer-Tests-02
    }
}

/// Tutorial 05, "Reacting to child events" section: the same News Feed example, now with
/// `favorites` owned once by the root via `MiddlewareReducer` instead of duplicated in
/// `NewsFeedListReducer` and `NewsFeedArticleReducer` above. Nested in its own namespace only
/// so this file can compile both the "before" (duplicated, `Tutorial05Reducer` above) and
/// "after" (deduplicated, here) versions side by side — the tutorial reader never sees this
/// namespace, only the unqualified type names extracted from inside it.
extension Tutorial05Reducer {

    enum Favorites {

        // @extract:begin Scopes-Reducer-NewsFeed-03
        @Reducer
        struct NewsFeedReducer: MiddlewareReducer {
            struct State: Injectable {
                static var defaultValue: State { State() }
                var loadingFeatureToggles: Bool = true
                var favorites: [Favorite] = []
                @SubState var atList: NewsFeedListReducer.State?
            }

            enum When {
                case systemLoadedScope
                case featureTogglesLoaded(favoritesEnabled: Bool)
                case toggleFavorite(id: String)
            }

            static func update(
                _ when: When,
                state: inout State,
                effectsState: inout EffectsState<When>,
                dependencies: ReducerDependencies
            ) throws {
                switch when {
                case .systemLoadedScope:
                    state.loadingFeatureToggles = true
                    // The root is now the single owner of `favorites` — load it once here,
                    // instead of every child loading its own copy on its own systemLoadedScope.
                    let persistence: PersistenceProvider = try dependencies.resolve()
                    state.favorites = try persistence.get()
                    // Simulate loading feature toggles
                    effectsState.enqueue(
                        AnyEffect { true }  // Simulate favoritesEnabled = true
                            .map { When.featureTogglesLoaded(favoritesEnabled: $0) }
                    )

                case .featureTogglesLoaded(let favoritesEnabled):
                    state.loadingFeatureToggles = false
                    // Create child scope with feature toggle parameter
                    var listState = NewsFeedListReducer.State()
                    listState.favoritesEnabled = favoritesEnabled
                    state.atList = listState

                case .toggleFavorite(let id):
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

            // Both NewsFeedListReducer and NewsFeedArticleReducer send `.favorite(id:)` — this
            // single updateSubstate catches it from either one, no matter how deep in the tree
            // it was sent.
            static func updateSubstate<Child: Reducer>(
                _ childType: Child.Type,
                childState: Child.State,
                childWhen: Child.When,
                parentState: State,
                dependencies: ReducerDependencies
            ) throws -> When? {
                if let listWhen = childWhen as? NewsFeedListReducer.When,
                   case .favorite(let id) = listWhen {
                    return .toggleFavorite(id: id)
                }
                if let articleWhen = childWhen as? NewsFeedArticleReducer.When,
                   case .favorite(let id) = articleWhen {
                    return .toggleFavorite(id: id)
                }
                return nil
            }
        }
        // @extract:end Scopes-Reducer-NewsFeed-03

        // @extract:begin Scopes-Reducer-NewsFeedList-03
        @Reducer
        struct NewsFeedListReducer {
            struct State: Injectable {
                static var defaultValue: State { State() }
                var favoritesEnabled: Bool = false
                var loading: Bool = false
                var loadedDTO: FeedListDTO?
                @SubState var readingArticle: NewsFeedArticleReducer.State?

                // No more local `favorites` copy — reads the root's canonical list directly.
                // NewsFeedListReducer implements no MiddlewareReducer at all; it doesn't need
                // to, since the root reacts to `.favorite` from this reducer's own When
                // without any relay code here (see the next type, where Article sends the
                // same event two levels further down and the root still reacts to it directly).
                @SuperState var newsFeed: NewsFeedReducer.State
            }

            enum When {
                case systemLoadedScope
                case networkListDidFinish(FeedListDTO)
                case navigateFromListToChild(id: String)
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
                    state.loading = true
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
                    state.loading = false
                    state.loadedDTO = dto

                case .navigateFromListToChild(let id):
                    // Create child article scope
                    var articleState = NewsFeedArticleReducer.State()
                    articleState.favoritesEnabled = state.favoritesEnabled
                    articleState.id = id
                    state.readingArticle = articleState

                case .favorite:
                    // A no-op here: this reducer no longer owns `favorites`, so its own
                    // update() has nothing left to do with the event — it still runs (forwarding
                    // always happens), it just does nothing. NewsFeedReducer.updateSubstate
                    // reacts to it afterward. Kept here only because `When` must stay
                    // exhaustive — the case itself is still what the view sends.
                    break
                }
            }
        }
        // @extract:end Scopes-Reducer-NewsFeedList-03

        // @extract:begin Scopes-Reducer-NewsFeedArticle-03
        @Reducer
        struct NewsFeedArticleReducer {
            struct State: Injectable {
                static var defaultValue: State { State() }
                var favoritesEnabled: Bool = false
                var id: String = ""
                var loading: Bool = false
                var loadedDTO: ArticleDTO?

                // Skips the direct parent (NewsFeedListReducer) and reads the root two levels
                // up — safe here because `favorites` is declared directly on NewsFeedReducer's
                // own State, not mirrored from somewhere else.
                @SuperState var newsFeed: NewsFeedReducer.State
            }

            enum When {
                case systemLoadedScope
                case networkDidFinish(ArticleDTO)
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
                    let articleId = state.id  // Copy to avoid capturing inout parameter

                    state.loading = true
                    effectsState.enqueue(
                        AnyEffect {
                            ArticleDTO(id: articleId, title: "Article \(articleId)", content: "Content for \(articleId)")
                        }
                        .map(When.networkDidFinish)
                    )

                case .networkDidFinish(let dto):
                    state.loading = false
                    state.loadedDTO = dto

                case .favorite:
                    // Same no-op as NewsFeedListReducer's own `.favorite` case above —
                    // NewsFeedReducer.updateSubstate reacts to it after this runs.
                    break
                }
            }
        }
        // @extract:end Scopes-Reducer-NewsFeedArticle-03

        final class MiddlewareReducerTests: XCTestCase {
            // @extract:begin Scopes-Reducer-Tests-03
            func testGrandchildFavoriteReachesRootAcrossTwoLevels() throws {
                let fixedDate = Date(timeIntervalSince1970: 1000)

                try NewsFeedReducer.Store.GIVEN(state: NewsFeedReducer.State()) { $0
                    .injectObject(DateProvider { fixedDate })
                    .injectObject(PersistenceProvider(get: { [] }, set: { _ in }))
                }
                .WHEN(.systemLoadedScope)
                .WHEN_OlderEffectCompletes(with: .featureTogglesLoaded(favoritesEnabled: true))
                .WHEN(\.children.atList, .navigateFromListToChild(id: "1"))
                // Three levels apart: root -> atList -> readingArticle. NewsFeedListReducer
                // implements no MiddlewareReducer at all, yet the root still reacts to this
                // grandchild's event directly.
                .WHEN(\.children.atList?.children.readingArticle, .favorite(id: "1"))
                .THEN(\.state.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
                .runTest()
            }
            // @extract:end Scopes-Reducer-Tests-03
        }
    }
}
