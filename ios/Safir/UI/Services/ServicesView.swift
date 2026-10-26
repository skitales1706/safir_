import SwiftUI

/// Services tab (Android ServicesScreen): live weather card, Ёвар AI, exchange rates and news,
/// then a carousel of top stories. Every card opens its screen with a zoom transition (iOS 18).
struct ServicesView: View {
    private var store: ServicesStore { .shared }
    @Namespace private var zoom
    /// Cards push by appending here (plain Buttons; more dependable than NavigationLink in cards).
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TabHeader(title: "Сервисы", subtitle: Self.today) { EmptyView() }
                        .padding(.horizontal, -16)
                        .appearIn(0)
                    weatherCard.appearIn(1)
                    assistantCard.appearIn(2)
                    HStack(spacing: 12) {
                        card(.currency, id: "currency") {
                            ServiceTile(icon: "dollarsign.arrow.circlepath", title: "Курсы валют", value: usdText)
                        }
                        card(.news, id: "news") {
                            ServiceTile(icon: "newspaper.fill", title: "Новости", value: newsText)
                        }
                    }
                    .appearIn(3)
                    if !store.news.isEmpty {
                        carousel.appearIn(4)
                    }
                    if store.failed && store.news.isEmpty && store.weather.isEmpty {
                        Label("Нет соединения с сервером", systemImage: "wifi.slash")
                            .font(.subheadline).foregroundStyle(Safir.muted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
            .tabBarClearance()
            .background(Safir.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            // The bar belongs to the tab's root screen: a pushed chat or page covers it.
            .safirTabBar()
            .refreshable { await store.load(force: true) }
            .task { await store.load() }
            .navigationDestination(for: ServiceRoute.self) { route in
                switch route {
                case .assistant: AssistantView().zoomDestination("ai", in: zoom)
                case .weather: WeatherView().zoomDestination("weather", in: zoom)
                case .currency: CurrencyView().zoomDestination("currency", in: zoom)
                case .news: NewsListView().zoomDestination("news", in: zoom)
                }
            }
            .navigationDestination(for: NewsDTO.self) { item in
                NewsArticleView(item: item).zoomDestination("article-\(item.id)", in: zoom)
            }
        }
    }

    // MARK: Cards

    /// A tappable card that opens `route`, zooming out of itself on iOS 18.
    private func card<Label: View>(_ route: ServiceRoute, id: String, @ViewBuilder label: () -> Label) -> some View {
        Button {
            Safir.tap()
            path.append(route)
        } label: {
            label()
        }
        .buttonStyle(CardPressStyle())
        .zoomSource(id, in: zoom)
        .accessibilityIdentifier("service-\(id)")
    }

    @ViewBuilder
    private var weatherCard: some View {
        if let city = store.city {
            let kind = WeatherKind(code: city.current.code)
            card(.weather, id: "weather") {
                ZStack {
                    SkyView(kind: kind, day: city.current.isDay)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(city.title, systemImage: "location.fill").font(.subheadline.weight(.semibold))
                            Text("\(city.current.temp ?? 0)°")
                                .font(.system(size: 58, weight: .thin, design: .rounded))
                                .contentTransition(.numericText())
                            Text(kind.title).font(.subheadline.weight(.medium))
                            if let today = city.today {
                                Text("Макс. \(today.max ?? 0)°  Мин. \(today.min ?? 0)°").font(.caption).opacity(0.85)
                            }
                        }
                        Spacer()
                        // A clear daytime sky already draws its sun.
                        if !(city.current.isDay && (kind == .clear || kind == .partly)) {
                            Image(systemName: kind.symbol(day: city.current.isDay))
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 46))
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                }
                .frame(height: 176)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                // The sky ignores touches, so without this only the text was tappable.
                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: kind.sky(day: city.current.isDay)[0].opacity(0.35), radius: 14, y: 8)
            }
        } else {
            card(.weather, id: "weather") {
                HStack {
                    Label("Погода", systemImage: "cloud.sun.fill").font(.title3.weight(.semibold))
                    Spacer()
                    if store.loading { ProgressView().tint(.white) }
                }
                .foregroundStyle(.white)
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Safir.brandGradient))
            }
        }
    }

    private var assistantCard: some View {
        card(.assistant, id: "ai") {
            HStack(spacing: 14) {
                AssistantOrb(size: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ёвар — ИИ-помощник").font(.headline).foregroundStyle(Safir.text)
                    Text("Тексты, переводы, идеи — спросите что угодно")
                        .font(.subheadline).foregroundStyle(Safir.muted).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Safir.muted)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Safir.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(LinearGradient(colors: [Safir.accent.opacity(0.6), Safir.accent.opacity(0.05)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2))
        }
    }

    /// Top stories, swiped sideways; cards shrink and dim as they leave the centre.
    private var carousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Главные новости").font(.title3.bold()).foregroundStyle(Safir.text)
                Spacer()
                Button("Все") { path.append(ServiceRoute.news) }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Safir.accent)
            }
            .padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(store.news.prefix(8)) { item in
                        Button { path.append(item) } label: {
                            NewsHeroCard(item: item, height: 200).frame(width: 290)
                        }
                        .buttonStyle(CardPressStyle())
                        .zoomSource("article-\(item.id)", in: zoom)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.92)
                                .opacity(phase.isIdentity ? 1 : 0.75)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .padding(.horizontal, -16)
        }
    }

    // MARK: Text

    private var usdText: String {
        guard let usd = store.exchange?.rates.first(where: { $0.code == "USD" }) else { return "Курс НБТ" }
        return "1 $ = \(CurrencyView.format(usd.perUnit, digits: 4)) с."
    }

    private var newsText: String {
        store.news.isEmpty ? "Свежие новости" : countText(store.news.count, ("новость", "новости", "новостей"))
    }

    private static var today: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: Date()).capitalized
    }
}

/// Square card: icon in a soft accent square, title and a live value.
private struct ServiceTile: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Safir.accent)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Safir.accent.opacity(0.14)))
            Spacer(minLength: 0)
            Text(title).font(.headline).foregroundStyle(Safir.text)
            Text(value).font(.caption).foregroundStyle(Safir.muted).lineLimit(1).minimumScaleFactor(0.8)
                .contentTransition(.numericText())
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Safir.card))
    }
}
