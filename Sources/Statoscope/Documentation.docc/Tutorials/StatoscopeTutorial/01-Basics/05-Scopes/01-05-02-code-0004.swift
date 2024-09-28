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
            isPresented: Binding(
                get: {
                    model.readingArticle != nil
                },
                set: { isPresented in
                    model.send(
                        .navigateToChild(
                            id: isPresented ? model.readingArticle?.id : nil
                        )
                    )
                }
            )
        ) {
            if let readingArticle = model.readingArticle {
                ArticleView(model: readingArticle)
            }
        }
    }
}
