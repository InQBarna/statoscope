final class NewsFeed: Statostore, ObservableObject {

    @Published var loadingFeatureToggles: Bool = true
    var atList: NewsFeedList?
    
    enum When {
        case systemLoadedScope
        case networkReturnsFeatureToggle(Result<[String: String], EquatableError>)
    }
    
    @Injected var network: NetworkProvider
    func update(_ when: When) throws { }
}

final class NewsFeedList: Statostore, ObservableObject {
    
    @Published var loadingList: Bool = false
    @Published var loadedListDTO: DTO.FeedList?
    @Published var readingArticleId: String?
    @Published var loadingArticle: Bool = false
    @Published var loadedArticleDTO: DTO.Article?
    @Published var favorites: [Favorite] = []
    
    enum When {
        case networkListDidFinish(DTO.FeedList)
        case navigateFromListToChild(id: String)
        case networkDidFinish(DTO.Article)
        case favorite(id: String)
    }
    
    @Injected var date: DateProvider
    @Injected var persistence: PersistenceProvider
    @Injected var network: NetworkProvider
    func update(_ when: When) throws { }
}
