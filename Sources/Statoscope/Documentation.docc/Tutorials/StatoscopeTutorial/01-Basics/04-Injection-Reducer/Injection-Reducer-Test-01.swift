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
