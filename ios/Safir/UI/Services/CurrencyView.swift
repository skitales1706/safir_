import SwiftUI

/// Exchange rates (Android CurrencyScreen): converter card (TJS <-> any NBT currency, the number
/// rolls as you type, the swap button turns) and every National Bank rate below it.
struct CurrencyView: View {
    private var store: ServicesStore { .shared }
    @State private var amount = "100"
    @State private var code = "USD"
    @State private var fromTJS = false
    @State private var swapTurns = 0.0
    @State private var query = ""
    @FocusState private var editing: Bool

    private var rates: [RateDTO] { store.exchange?.rates ?? [] }
    private var selected: RateDTO? { rates.first { $0.code == code } ?? rates.first }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    converter.id("top").appearIn(0)
                    if let date = store.exchange?.date {
                        HStack {
                            Text("Курс НБТ на \(date)").font(.headline).foregroundStyle(Safir.text)
                            Spacer()
                            Text("сомони").font(.caption).foregroundStyle(Safir.muted)
                        }
                        .padding(.top, 6)
                        .appearIn(1)
                    }
                    SearchCapsule(text: $query, prompt: "Валюта").padding(.horizontal, -16).appearIn(1)
                    LazyVStack(spacing: 8) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, rate in
                            Button {
                                Safir.tap()
                                editing = false
                                withAnimation(Safir.spring) {
                                    code = rate.code
                                    proxy.scrollTo("top", anchor: .top)
                                }
                            } label: {
                                rateRow(rate)
                            }
                            .buttonStyle(CardPressStyle())
                            .appearIn(Swift.min(i, 10) + 2)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .tabBarClearance()
            .refreshable { await store.load(force: true) }
        }
        .background(Safir.background.ignoresSafeArea())
        .navigationTitle("Курсы валют")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if rates.isEmpty && !store.loading {
                EmptyStateView(icon: "dollarsign.circle", title: "Курсы не загружены", subtitle: "Проверьте соединение с сервером")
            }
        }
        .task { await store.load() }
    }

    // MARK: Converter

    private var converter: some View {
        let value = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        let perUnit = selected?.perUnit ?? 0
        let result = fromTJS ? (perUnit > 0 ? value / perUnit : 0) : value * perUnit
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Конвертер", systemImage: "arrow.left.arrow.right").font(.subheadline.weight(.semibold))
                Spacer()
                if let selected {
                    Text("1 \(selected.code) = \(Self.format(selected.perUnit, digits: 4)) TJS")
                        .font(.caption.weight(.medium)).opacity(0.85)
                        .contentTransition(.numericText())
                }
            }
            HStack(spacing: 10) {
                currencyBadge(fromTJS ? nil : selected)
                TextField("0", text: $amount)
                    .keyboardType(.decimalPad)
                    .focused($editing)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Rectangle().fill(.white.opacity(0.25)).frame(height: 1)
                Button {
                    Safir.tap(.medium)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                        fromTJS.toggle()
                        swapTurns += 180
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Safir.accentDeep)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.white))
                        .rotationEffect(.degrees(swapTurns))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Поменять местами")
                Rectangle().fill(.white.opacity(0.25)).frame(height: 1)
            }
            HStack(spacing: 10) {
                currencyBadge(fromTJS ? selected : nil)
                Spacer()
                Text(Self.format(result, digits: 2))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: result))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: result)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .padding(18)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Safir.brandGradient)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(.white.opacity(0.08)).frame(width: 180).offset(x: 60, y: -70)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: Safir.accent.opacity(0.35), radius: 16, y: 8)
        }
        .padding(.top, 8)
    }

    /// Flag + code; nil = somoni. Tapping opens the currency menu.
    private func currencyBadge(_ rate: RateDTO?) -> some View {
        Menu {
            ForEach(rates) { r in
                Button("\(r.flag) \(r.code) — \(r.name)") {
                    withAnimation(Safir.spring) { code = r.code }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(rate?.flag ?? "🇹🇯").font(.title2)
                Text(rate?.code ?? "TJS").font(.headline)
                if rate != nil {
                    Image(systemName: "chevron.down").font(.caption2.bold())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 40)
            .background(.white.opacity(0.18), in: Capsule())
        }
        .disabled(rate == nil)
    }

    // MARK: Rates

    private var shown: [RateDTO] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return rates }
        return rates.filter { $0.code.lowercased().contains(q) || $0.name.lowercased().contains(q) }
    }

    private func rateRow(_ rate: RateDTO) -> some View {
        let isSelected = rate.code == selected?.code
        return HStack(spacing: 12) {
            Text(rate.flag).font(.system(size: 28))
                .frame(width: 46, height: 46)
                .background(Circle().fill(Safir.pill))
            VStack(alignment: .leading, spacing: 2) {
                Text(rate.code).font(.headline).foregroundStyle(Safir.text)
                Text(rate.name).font(.caption).foregroundStyle(Safir.muted).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(rate.rate).font(.headline.monospacedDigit()).foregroundStyle(Safir.text)
                Text(rate.unit == 1 ? "сомони" : "за \(rate.unit) \(rate.code)").font(.caption).foregroundStyle(Safir.muted)
            }
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Safir.accent)
                .opacity(isSelected ? 1 : 0)
                .scaleEffect(isSelected ? 1 : 0.5)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Safir.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(isSelected ? Safir.accent.opacity(0.5) : .clear, lineWidth: 1.5))
    }

    static func format(_ value: Double, digits: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "ru_RU")
        f.maximumFractionDigits = digits
        f.minimumFractionDigits = digits == 4 ? 2 : 0
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }
}
