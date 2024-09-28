struct ListView: View {
    @ObservedObject var model: NewsFeedList
    var body: some View {
        NavigationStack {
            ZStack {
                List(model.loadedDTO?.news ?? [], id: \.id) { item in
                    Text(item.title)
                        .frame(maxWidth: .infinity)
                        .onTapGesture { _ in
                            model.send(.navigateToChild(id: item.id))
                        }
                }
                if model.loading {
                    ProgressView()
                }
            }
        }
        .navigationTitle("News")
        .navigationDestination(
            isPresented: model.bindIsPresented(\.readingArticle?.id, NewsFeedList.When.navigateToChild)
        ) {
            if let readingArticle = model.readingArticle {
                ArticleView(model: readingArticle)
            }
        }
    }
}

struct ArticleView: View {
    @ObservedObject var model: NewsFeedArticle
    var body: some View {
        ZStack {
            Text(model.loadedDTO?.contentMarkdown ?? "")
            if model.loading {
                ProgressView()
            }
        }
        .navigationTitle(model.loadedDTO?.title ?? "")
    }
}