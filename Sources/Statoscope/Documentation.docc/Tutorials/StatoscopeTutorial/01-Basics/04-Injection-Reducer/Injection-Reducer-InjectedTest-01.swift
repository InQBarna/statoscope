func testInjectedValuesAreUsedWhenPresent() throws {
    struct FakeNetworkProvider: NetworkProvider {
        func fetchArticles() async throws -> [ArticleDTO] { [] }
    }
    let fixedDate = Date(timeIntervalSince1970: 1000)

    let store = NewsFeedStatusReducer.Store(initialState: .init())
        .injectObject(DateProvider { fixedDate })
        .injectObject(FakeNetworkProvider(), for: RealNetworkProvider.self)

    store.send(.checkNow)

    XCTAssertEqual(store.state.lastCheckedAt, fixedDate)
    XCTAssertTrue(store.state.network is FakeNetworkProvider)
}
