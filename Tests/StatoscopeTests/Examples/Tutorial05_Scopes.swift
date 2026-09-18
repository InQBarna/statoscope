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

/// Tutorial 05, "Reacting to child events" section: the same News Feed example, now with
/// `favorites` owned once by the root via `HierarchialScopeMiddleWare` instead of duplicated
/// in `NewsFeedList` and `NewsFeedArticle` above. Nested in its own namespace only so this
/// file can compile both the "before" (duplicated, `Tutorial05` above) and "after"
/// (deduplicated, here) versions side by side — the tutorial reader never sees this
/// namespace, only the unqualified type names extracted from inside it.
extension Tutorial05 {

    enum Favorites {

        // @extract:begin Scopes-NewsFeed-03
        final class NewsFeed: Statostore, ObservableObject, Injectable, HierarchialScopeMiddleWare {
            @Published var loadingFeatureToggles: Bool = true
            @Published var favorites: [Favorite] = []
            @Subscope var atList: NewsFeedList?

            enum When {
                case systemLoadedScope
                case featureTogglesLoaded(favoritesEnabled: Bool)
            }

            static var defaultValue: NewsFeed { NewsFeed() }

            @Injected var date: DateProvider
            @Injected var persistence: PersistenceProvider

            func update(_ when: When) throws {
                switch when {
                case .systemLoadedScope:
                    loadingFeatureToggles = true
                    // The root is now the single owner of `favorites` — load it once here,
                    // instead of every child loading its own copy on its own systemLoadedScope.
                    favorites = try persistence.get()
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

            // Both NewsFeedList and NewsFeedArticle send `.favorite(id:)` — this single
            // updateSubscope catches it from either one, no matter how deep in the tree it
            // was sent from. Unlike the Reducer pattern's updateSubstate, this can mutate
            // `self` directly — no need to delegate through a returned When processed by a
            // separate update() call.
            func updateSubscope<Child: ScopeImplementation>(_ event: SubscopeEvent<Child>) throws {
                if let listEvent = event as? SubscopeEvent<NewsFeedList>,
                   case .favorite(let id) = listEvent.when {
                    try toggleFavorite(id: id)
                    return  // consumed — the child has nothing left to do with .favorite
                }
                if let articleEvent = event as? SubscopeEvent<NewsFeedArticle>,
                   case .favorite(let id) = articleEvent.when {
                    try toggleFavorite(id: id)
                    return  // consumed — never calls event.forward()
                }
                try event.forward()
            }

            private func toggleFavorite(id: String) throws {
                if let favIndex = favorites.firstIndex(where: { $0.id == id }) {
                    favorites.remove(at: favIndex)
                } else {
                    favorites.append(Favorite(id: id, dateAdded: date.currentDate()))
                }
                try persistence.set(favorites)
            }
        }
        // @extract:end Scopes-NewsFeed-03

        // @extract:begin Scopes-NewsFeedList-03
        final class NewsFeedList: Statostore, ObservableObject {
            let favoritesEnabled: Bool

            @Published var loading: Bool = false
            @Published var loadedDTO: FeedListDTO?
            @Subscope var readingArticle: NewsFeedArticle?

            // No more local `favorites` copy — reads the root's canonical list directly.
            // NewsFeedList implements no HierarchialScopeMiddleWare at all; it doesn't need
            // to, since the root intercepts `.favorite` from this scope's own When without any
            // relay code here (see the next type, where Article sends the same event two
            // levels further down and the root still catches it directly).
            @Superscope(observed: true) var newsFeed: NewsFeed

            enum When {
                case systemLoadedScope
                case networkListDidFinish(FeedListDTO)
                case navigateFromListToChild(id: String)
                case favorite(id: String)
            }

            init(favoritesEnabled: Bool) {
                self.favoritesEnabled = favoritesEnabled
            }

            func update(_ when: When) throws {
                switch when {
                case .systemLoadedScope:
                    loading = true
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

                case .favorite:
                    // Never reached: NewsFeed.updateSubscope consumes this event (never calls
                    // event.forward() for it) — kept here only because `When` must stay
                    // exhaustive. The case itself is still what the view sends.
                    break
                }
            }
        }
        // @extract:end Scopes-NewsFeedList-03

        // @extract:begin Scopes-NewsFeedArticle-03
        final class NewsFeedArticle: Statostore, ObservableObject {
            let favoritesEnabled: Bool
            let id: String

            @Published var loading: Bool = false
            @Published var loadedDTO: ArticleDTO?

            // Skips the direct parent (NewsFeedList) and reads the root two levels up —
            // always safe here, because @Superscope resolves to a LIVE REFERENCE to the
            // actual ancestor object, not a value snapshot copied at some point in time.
            // There's no equivalent of the Reducer pattern's "stale cached mirror" gotcha to
            // worry about — reading through it always reflects the ancestor's current state.
            @Superscope(observed: true) var newsFeed: NewsFeed

            enum When {
                case systemLoadedScope
                case networkDidFinish(ArticleDTO)
                case favorite(id: String)
            }

            init(favoritesEnabled: Bool, id: String) {
                self.favoritesEnabled = favoritesEnabled
                self.id = id
            }

            func update(_ when: When) throws {
                switch when {
                case .systemLoadedScope:
                    loading = true
                    effectsState.enqueue(
                        AnyEffect {
                            ArticleDTO(id: self.id, title: "Article \(self.id)", content: "Content for \(self.id)")
                        }
                        .map(When.networkDidFinish)
                    )

                case .networkDidFinish(let dto):
                    loading = false
                    loadedDTO = dto

                case .favorite:
                    // Never reached: NewsFeed.updateSubscope consumes this event before it
                    // gets here.
                    break
                }
            }
        }
        // @extract:end Scopes-NewsFeedArticle-03

        final class MiddlewareTests: XCTestCase {
            // @extract:begin Scopes-Tests-03
            func testGrandchildFavoriteReachesRootAcrossTwoLevels() throws {
                let fixedDate = Date(timeIntervalSince1970: 1000)

                try NewsFeed.GIVEN {
                    NewsFeed()
                        .injectObject(DateProvider { fixedDate })
                        .injectObject(PersistenceProvider(get: { [] }, set: { _ in }))
                }
                .WHEN(.systemLoadedScope)
                .WHEN_OlderEffectCompletes(with: .featureTogglesLoaded(favoritesEnabled: true))
                .WHEN(\.atList, .navigateFromListToChild(id: "1"))
                // Three levels apart: root -> atList -> readingArticle. NewsFeedList
                // implements no HierarchialScopeMiddleWare at all, yet the root still
                // intercepts this grandchild's event directly.
                .WHEN(\.atList?.readingArticle, .favorite(id: "1"))
                .THEN(\.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
                .runTest()
            }
            // @extract:end Scopes-Tests-03
        }
    }
}
