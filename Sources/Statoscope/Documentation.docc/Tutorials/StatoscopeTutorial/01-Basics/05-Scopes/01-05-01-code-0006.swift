final class NewsFeed: Statostore, ObservableObject {

    @Published var loadingFeatureToggles: Bool = true
    @Subscope var atList: NewsFeedList?
    
    enum When {
        case systemLoadedScope
        case networkReturnsFeatureToggle(Result<[String: String], EquatableError>)
    }
    
    @Injected var network: NetworkProvider
    func update(_ when: When) throws { }
}

final class NewsFeedList: Statostore, ObservableObject {
    
    let favoritesEnabled: Bool
    @Published var loadingList: Bool = false
    @Published var loadedListDTO: DTO.FeedList?
    @Published var favorites: [Favorite] = []
    
    enum When {
        case networkListDidFinish(DTO.FeedList)
        case navigateFromListToChild(id: String)
        case favorite(id: String)
    }
    
    init(favoritesEnabled: Bool) { self.favoritesEnabled = favoritesEnabled }
    @Injected var date: DateProvider
    @Injected var persistence: PersistenceProvider
    @Injected var network: NetworkProvider
    func update(_ when: When) throws { }
}
