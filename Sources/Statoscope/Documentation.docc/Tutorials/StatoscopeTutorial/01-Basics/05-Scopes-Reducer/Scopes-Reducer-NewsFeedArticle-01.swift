@Reducer
struct NewsFeedArticleReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        var favoritesEnabled: Bool = false
        var id: String = ""
        var loading: Bool = false
        var loadedDTO: ArticleDTO?
        var favorites: [Favorite] = []
    }

    enum When {
        case systemLoadedScope
        case networkDidFinish(ArticleDTO)
        case favorite(id: String)
    }
