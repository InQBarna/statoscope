// A real Swift protocol, not an Injectable struct-of-closures: NetworkProvider has more than
// one plausible conformance (the real network call, a fake for tests), which is exactly what
// protocol-typed injection is for. DateProvider/PersistenceProvider above are Injectable
// because they only ever have ONE real shape; NetworkProvider doesn't.
protocol NetworkProvider {
    func fetchArticles() async throws -> [ArticleDTO]
}

// RealNetworkProvider also conforms to Injectable itself — needed the moment NetworkProvider
// is read declaratively (@ReducerInjected, below in Tutorial04b_ReducerInjected.swift) rather
// than imperatively via dependencies.resolve(): a declarative property wrapper must never
// throw, so it needs a default to fall back to. Declaring defaultValue with a protocol return
// type instead of Self is all that's needed — no separate mechanism. dependencies.resolve()
// below still won't consult it — it's for the OTHER section.
struct RealNetworkProvider: NetworkProvider, Injectable {
    static var defaultValue: NetworkProvider { RealNetworkProvider() }

    func fetchArticles() async throws -> [ArticleDTO] {
        let url = URL(string: "https://api.example.com/articles")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([ArticleDTO].self, from: data)
    }
}

struct ArticleDTO: Codable, Equatable {
    let id: String
    let title: String
    let content: String
}
