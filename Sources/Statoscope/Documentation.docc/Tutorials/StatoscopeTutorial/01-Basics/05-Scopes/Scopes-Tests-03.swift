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
