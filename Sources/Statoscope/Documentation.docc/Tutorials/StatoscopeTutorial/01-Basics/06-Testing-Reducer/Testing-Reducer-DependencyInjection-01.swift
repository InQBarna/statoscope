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
