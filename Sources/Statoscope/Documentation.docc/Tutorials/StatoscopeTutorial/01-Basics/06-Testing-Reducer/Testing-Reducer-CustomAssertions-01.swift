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
