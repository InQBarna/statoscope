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
    // implements no MiddlewareReducer at all, yet the root still intercepts this
    // grandchild's event directly.
    .WHEN(\.children.atList?.children.readingArticle, .favorite(id: "1"))
    .THEN(\.state.favorites, equals: [Favorite(id: "1", dateAdded: fixedDate)])
    .runTest()
}
