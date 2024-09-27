import Statoscope

struct DateProvider: Injectable { /* ... */ }
struct PersistenceProvider: Injectable { /* ... */ }

final class NewsFeedList: Statostore {
    
    // Scope state
    var loading: Bool = false
    var loadedDTOs: DTO?
    var readingArticle: URL?
    var favorites: [Favorite] = []
    
    // Scope When events
    enum When {
        case systemLoadedScope
        case networkDidFinish(DTO)
        case navigateToChild(id: String)
        case favorite(id: String)
    }
    
    // Dependencies
    @Injected var date: DateProvider
    @Injected var persistence: PersistenceProvider
    
    // Implementation
    func update(_ when: When) throws {
        switch when {
        case .systemLoadedScope:
            loading = true
            loadedDTOs = nil
            favorites = try persistence.get()
        case .networkDidFinish(let dtos):
            loading = false
            loadedDTOs = dtos
        case .navigateToChild(let id):
            guard let article = loadedDTOs?.news.first(where: { $0.id == id }) else {
                throw InvalidStateError()
            }
            guard let articleUrl = URL(string: article.url) else {
                throw "Invalid article"
            }
            readingArticle = articleUrl
        case .favorite(let id):
            if let favIndex = favorites.firstIndex(where: { $0.id == id }) {
                favorites.remove(at: favIndex)
            } else {
                favorites.append(Favorite(id: id, dateAdded: date.currentDate()))
            }
            try persistence.set(favorites)
        }
    }
}
