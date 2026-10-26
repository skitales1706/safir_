import SwiftUI

/// News feed (Android NewsScreen): category chips with a sliding highlight, a big hero card for
/// the top story, then compact cards. Articles (NewsDTO values) are pushed by the hub's stack.
struct NewsListView: View {
    private var store: ServicesStore { .shared }
    @State private var category: String?
    @Namespace private var chipNS

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                chips.padding(.horizontal, -16).appearIn(0)
                if let top = shown.first {
                    NavigationLink(value: top) {
                        NewsHeroCard(item: top)
                    }
                    .buttonStyle(CardPressStyle())
                    .appearIn(1)
                }
                ForEach(Array(shown.dropFirst().enumerated()), id: \.element.id) { i, item in
                    NavigationLink(value: item) {
                        NewsRowCard(item: item)
                    }
                    .buttonStyle(CardPressStyle())
                    .appearIn(Swift.min(i, 8) + 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .id(category)
        }
        .tabBarClearance()
        .refreshable { await store.load(force: true) }
        .background(Safir.background.ignoresSafeArea())
        .navigationTitle("Новости")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if store.news.isEmpty && !store.loading {
                EmptyStateView(icon: "newspaper", title: "Новостей пока нет", subtitle: "Проверьте соединение с сервером")
            }
        }
        .task { await store.load() }
    }

    private var categories: [String] {
        var seen = Set<String>()
        return store.news.compactMap(\.category).filter { seen.insert($0).inserted }
    }

    private var shown: [NewsDTO] {
        guard let category else { return store.news }
        return store.news.filter { $0.category == category }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, "Все")
                ForEach(categories, id: \.self) { chip($0, $0) }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ value: String?, _ title: String) -> some View {
        let isOn = category == value
        return Button {
            Safir.tap()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { category = value }
        } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? .white : Safir.muted)
                .padding(.horizontal, 16).frame(height: 36)
                .background {
                    if isOn {
                        Capsule().fill(Safir.brandGradient).matchedGeometryEffect(id: "chip", in: chipNS)
                    } else {
                        Capsule().fill(Safir.pill)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// Top story: full-width photo, dark fade, white title.
struct NewsHeroCard: View {
    let item: NewsDTO
    var height: CGFloat = 230

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: item.imageUrl, icon: false)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                if let category = item.category {
                    Text(category.uppercased()).font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .safirGlass(in: Capsule())
                }
                Text(item.title ?? "").font(.headline).lineLimit(3).multilineTextAlignment(.leading)
                Text(item.meta).font(.caption).opacity(0.85).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

/// Title, source and a square thumbnail.
struct NewsRowCard: View {
    let item: NewsDTO

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if let category = item.category {
                    Text(category).font(.caption.weight(.semibold)).foregroundStyle(Safir.accent)
                }
                Text(item.title ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(Safir.text)
                    .lineLimit(3).multilineTextAlignment(.leading)
                Text(item.meta).font(.caption).foregroundStyle(Safir.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            RemoteImage(url: item.imageUrl)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Safir.card))
    }
}

/// Article: photo header that stretches when pulled down, then the text; share and source.
struct NewsArticleView: View {
    let item: NewsDTO
    @State private var shown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { geo in
                    let pull = Swift.max(geo.frame(in: .scrollView).minY, 0)
                    RemoteImage(url: item.imageUrl)
                        .frame(width: geo.size.width, height: 280 + pull)
                        .clipped()
                        .offset(y: -pull)
                }
                .frame(height: 280)

                VStack(alignment: .leading, spacing: 12) {
                    if let category = item.category {
                        Text(category.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Safir.accent)
                    }
                    Text(item.title ?? "").font(.title2.bold()).foregroundStyle(Safir.text)
                    Label(item.meta, systemImage: "clock").font(.footnote).foregroundStyle(Safir.muted)
                    Text(item.content ?? "")
                        .font(.body).lineSpacing(4)
                        .foregroundStyle(Safir.text)
                        .textSelection(.enabled)
                    if let link = item.newsUrl.flatMap(URL.init(string:)) {
                        Link(destination: link) {
                            Label("Читать в источнике", systemImage: "safari")
                                .font(.headline)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .foregroundStyle(.white)
                                .background(Capsule().fill(Safir.brandGradient))
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous)
                        .fill(Safir.background)
                )
                .offset(y: shown ? -26 : 4)
                .opacity(shown ? 1 : 0)
            }
        }
        .ignoresSafeArea(edges: .top)
        .tabBarClearance()
        .background(Safir.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let link = item.newsUrl.flatMap(URL.init(string:)) {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: link) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.1)) { shown = true }
        }
    }
}
