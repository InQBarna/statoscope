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
