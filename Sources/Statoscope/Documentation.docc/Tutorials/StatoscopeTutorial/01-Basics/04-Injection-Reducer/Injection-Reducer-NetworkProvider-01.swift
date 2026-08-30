struct NetworkProvider: Injectable {
    let fetchArticles: () async throws -> [ArticleDTO]

    static var defaultValue = NetworkProvider(
        fetchArticles: {
            let url = URL(string: "https://api.example.com/articles")!
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode([ArticleDTO].self, from: data)
        }
    )
}

struct ArticleDTO: Codable, Equatable {
    let id: String
    let title: String
    let content: String
}
