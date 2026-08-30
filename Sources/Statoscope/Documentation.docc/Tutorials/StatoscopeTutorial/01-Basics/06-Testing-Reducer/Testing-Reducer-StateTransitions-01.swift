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
