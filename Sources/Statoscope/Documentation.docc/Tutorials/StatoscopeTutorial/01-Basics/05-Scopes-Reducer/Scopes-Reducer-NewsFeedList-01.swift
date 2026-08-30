@Reducer
struct NewsFeedListReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        var favoritesEnabled: Bool = false
        var loading: Bool = false
        var loadedDTO: FeedListDTO?
        @SubState var readingArticle: NewsFeedArticleReducer.State?
        var favorites: [Favorite] = []
    }

    enum When {
        case systemLoadedScope
        case networkListDidFinish(FeedListDTO)
        case navigateFromListToChild(id: String)
        case favorite(id: String)
    }
