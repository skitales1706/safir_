import SwiftUI

/// The last keyboard height above the home indicator, so the panel opens exactly where the
/// keyboard was and the composer stays level when switching (Telegram).
enum KeyboardMetrics {
    private static let key = "keyboard_height"

    static var panelHeight: CGFloat {
        let stored = UserDefaults.standard.double(forKey: key)
        return stored > 0 ? min(max(stored, 250), 420) : 300
    }

    /// From keyboardWillChangeFrame: remembers the height when the keyboard is up.
    static func record(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
        else { return }
        let height = window.bounds.maxY - window.convert(frame, from: nil).minY - window.safeAreaInsets.bottom
        if height > 150 { UserDefaults.standard.set(Double(height), forKey: key) }
    }
}

/// Telegram-style emoji / sticker panel in place of the keyboard (Android EmojiStickerPanel):
/// emoji go into the text field, a sticker is sent right away. The pill at the bottom switches
/// Эмодзи | Стикеры; the row on top jumps between categories.
struct EmojiPanel: View {
    let onPick: (String) -> Void
    var onBackspace: () -> Void = {}
    /// nil = emoji only (no stickers tab).
    var onSticker: ((StickerDef) -> Void)?
    var height: CGFloat = KeyboardMetrics.panelHeight
    @AppStorage("emoji_panel_tab") private var tab = 0
    @State private var recent: [String] = UserDefaults.standard.stringArray(forKey: "recent_emoji") ?? []
    @State private var selected = 0
    @Namespace private var pill

    static let categories: [(icon: String, items: String)] = [
        ("face.smiling", "😀😃😄😁😆😅😂🤣🥲😊😇🙂🙃😉😌😍🥰😘😗😙😚😋😛😝😜🤪🤨🧐🤓😎🥸🤩🥳😏😒😞😔😟😕🙁☹️😣😖😫😩🥺😢😭😤😠😡🤬🤯😳🥵🥶😱😨😰😥😓🤗🤔🫡🤭🫢🤫🤥😶😐😑😬🙄😯😦😧😮😲🥱😴🤤😪😵🤐🥴🤢🤮🤧😷🤒🤕🤑🤠😈👿👹👺🤡💩👻💀👽🤖🎃😺😸😹😻😼😽🙀😿😾"),
        ("hand.wave", "👋🤚🖐✋🖖👌🤌🤏✌️🤞🫰🤟🤘🤙👈👉👆👇☝️🫵👍👎✊👊🤛🤜👏🙌🫶👐🤲🤝🙏✍️💅🤳💪🦾🦵🦶👂🦻👃🧠🫀🫁🦷🦴👀👁👅👄👶🧒👦👧🧑👱👨🧔👩🧓👴👵🙍🙎🙅🙆💁🙋🧏🙇🤦🤷👮🕵️💂🥷👷🤴👸👳👲🧕🤵👰🤰🤱👼🎅🤶🦸🦹🧙🧚🧛🧜🧝🧞🧟💆💇🚶🧍🧎🏃💃🕺👯🧖🧗🤺🏇⛷🏂🏄🚣🏊🚴🚵🤸🤼🤽🤾🤹🧘🛀🛌👭👫👬💏💑👪"),
        ("pawprint", "🐶🐱🐭🐹🐰🦊🐻🐼🐨🐯🦁🐮🐷🐸🐵🙈🙉🙊🐒🐔🐧🐦🐤🐣🐥🦆🦅🦉🦇🐺🐗🐴🦄🐝🪱🐛🦋🐌🐞🐜🪰🪲🪳🦟🦗🕷🦂🐢🐍🦎🦖🦕🐙🦑🦐🦞🦀🐡🐠🐟🐬🐳🐋🦈🐊🐅🐆🦓🦍🦧🦣🐘🦛🦏🐪🐫🦒🦘🦬🐃🐂🐄🐎🐖🐏🐑🦙🐐🦌🐕🐩🦮🐈🐓🦃🦤🦚🦜🦢🦩🕊🐇🦝🦨🦡🦫🦦🦥🐁🐀🐿🦔🌵🎄🌲🌳🌴🪵🌱🌿☘️🍀🎍🪴🎋🍃🍂🍁🍄🐚🪨🌾💐🌷🌹🥀🌺🌸🌼🌻🌞🌝🌛🌜🌚🌕🌙🌎🪐💫⭐️🌟✨⚡️☄️💥🔥🌪🌈☀️🌤⛅️🌥☁️🌦🌧⛈🌩🌨❄️☃️⛄️🌬💨💧💦☔️☂️🌊"),
        ("fork.knife", "🍏🍎🍐🍊🍋🍌🍉🍇🍓🫐🍈🍒🍑🥭🍍🥥🥝🍅🍆🥑🥦🥬🥒🌶🫑🌽🥕🫒🧄🧅🥔🍠🥐🥯🍞🥖🥨🧀🥚🍳🧈🥞🧇🥓🥩🍗🍖🌭🍔🍟🍕🫓🥪🥙🧆🌮🌯🫔🥗🥘🫕🥫🍝🍜🍲🍛🍣🍱🥟🦪🍤🍙🍚🍘🍥🥠🥮🍢🍡🍧🍨🍦🥧🧁🍰🎂🍮🍭🍬🍫🍿🍩🍪🌰🥜🍯🥛🍼🫖☕️🍵🧃🥤🧋🍶🍺🍻🥂🍷🥃🍸🍹🧉🍾🧊🥄🍴🍽🥣🥡🥢🧂"),
        ("soccerball", "⚽️🏀🏈⚾️🥎🎾🏐🏉🥏🎱🪀🏓🏸🏒🏑🥍🏏🪃🥅⛳️🪁🏹🎣🤿🥊🥋🎽🛹🛼🛷⛸🥌🎿🪂🏆🥇🥈🥉🏅🎖🏵🎗🎫🎟🎪🎭🩰🎨🎬🎤🎧🎼🎹🥁🪘🎷🎺🪗🎸🪕🎻🎲♟🎯🎳🎮🎰🧩"),
        ("car.fill", "🚗🚕🚙🚌🚎🏎🚓🚑🚒🚐🛻🚚🚛🚜🛴🚲🛵🏍🛺🚨🚔🚍🚘🚖🚡🚠🚟🚃🚋🚞🚝🚄🚅🚈🚂🚆🚇🚊🚉✈️🛫🛬🛩💺🛰🚀🛸🚁🛶⛵️🚤🛥🛳⛴🚢⚓️⛽️🚧🚦🚥🚏🗺🗿🗽🗼🏰🏯🏟🎡🎢🎠⛲️⛱🏖🏝🏜🌋⛰🏔🗻🏕⛺️🏠🏡🏘🏚🏗🏭🏢🏬🏣🏤🏥🏦🏨🏪🏫🏩💒🏛⛪️🕌🕍🛕🕋⛩🛤🛣🗾🎑🏞🌅🌄🌠🎇🎆🌇🌆🏙🌃🌌🌉🌁"),
        ("lightbulb", "⌚️📱📲💻⌨️🖥🖨🖱🕹💽💾💿📀📷📸📹🎥📽🎞📞☎️📟📠📺📻🎙🎚🎛🧭⏱⏲⏰🕰⌛️⏳📡🔋🔌💡🔦🕯🪔🧯💸💵💴💶💷🪙💰💳💎⚖️🪜🧰🪛🔧🔨⚒🛠⛏🪚🔩⚙️🧱⛓🧲🧨🪓🔪🛡⚱️🏺🔮📿🧿💈⚗️🔭🔬🩹🩺💊💉🩸🧬🦠🧪🌡🧹🧺🧻🚽🚿🛁🧼🪥🧽🪣🧴🛎🔑🗝🚪🪑🛋🛏🧸🪆🖼🪞🪟🛍🛒🎁🎈🎏🎀🪄🪅🎊🎉🎎🏮🎐🧧✉️📩📨📧💌📥📤📦🏷📪📫📬📭📮📜📃📄📑🧾📊📈📉🗒🗓📆📅🗑📇🗃🗳🗄📋📁📂🗂🗞📰📓📔📒📕📗📘📙📚📖🔖🧷🔗📎🖇📐📏🧮📌📍✂️🖊🖋✒️🖌🖍📝✏️🔍🔎🔏🔐🔒🔓"),
        ("heart", "❤️🧡💛💚💙💜🖤🤍🤎💔❣️💕💞💓💗💖💘💝💟☮️☪️🕉☯️♈️♉️♊️♋️♌️♍️♎️♏️♐️♑️♒️♓️⚛️☢️☣️📴📳✴️🆚💮🅰️🅱️🆎🆑🅾️🆘❌⭕️🛑⛔️📛🚫💯💢♨️🚷🚯🚳🚱🔞📵🚭❗️❕❓❔‼️⁉️🔅🔆〽️⚠️🚸🔱⚜️🔰♻️✅💹❇️✳️❎🌐💠Ⓜ️🌀💤🏧🚾♿️🅿️🛗🛂🛃🛄🛅🚹🚺🚼🚻🚮🎦📶🔣ℹ️🔤🔡🔠🆖🆗🆙🆒🆕🆓🔟🔢▶️⏸⏯⏹⏺⏭⏮⏩⏪⏫⏬◀️🔼🔽➡️⬅️⬆️⬇️↗️↘️↙️↖️↕️↔️↪️↩️⤴️⤵️🔀🔁🔂🔄🔃🎵🎶➕➖➗✖️♾💲💱™️©️®️〰️➰➿🔚🔙🔛🔝🔜✔️☑️🔘🔴🟠🟡🟢🔵🟣⚫️⚪️🟤🔺🔻🔸🔹🔶🔷🔳🔲▪️▫️◾️◽️◼️◻️🟥🟧🟨🟩🟦🟪⬛️⬜️🟫🔈🔇🔉🔊🔔🔕📣📢💬💭🗯♠️♣️♥️♦️🃏🎴🀄️"),
        ("flag", "🇹🇯🇷🇺🇺🇿🇰🇿🇰🇬🇹🇲🇦🇫🇮🇷🇹🇷🇦🇿🇦🇲🇬🇪🇺🇦🇧🇾🇨🇳🇮🇳🇵🇰🇸🇦🇦🇪🇶🇦🇰🇼🇪🇬🇺🇸🇬🇧🇩🇪🇫🇷🇮🇹🇪🇸🇯🇵🇰🇷🏳️🏴🏁🚩🏳️‍🌈"),
    ]

    private var stickersOn: Bool { onSticker != nil && tab == 1 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if stickersOn, let onSticker {
                    StickerGrid(onPick: onSticker).transition(.opacity)
                } else {
                    emojiTab.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.18), value: stickersOn)
            bottomBar
        }
        .frame(height: height)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Safir.background.opacity(0.7)
            }
            .overlay(alignment: .top) { Rectangle().fill(Safir.separator.opacity(0.6)).frame(height: 0.5) }
            // Down under the home indicator, like the keyboard it replaces.
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var emojiTab: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        if !recent.isEmpty { categoryButton("clock", id: -1, proxy: proxy) }
                        ForEach(Self.categories.indices, id: \.self) { i in
                            categoryButton(Self.categories[i].icon, id: i, proxy: proxy)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                }
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 8), spacing: 6) {
                        if !recent.isEmpty {
                            section(tr("Недавние"), items: recent, id: -1)
                        }
                        ForEach(Self.categories.indices, id: \.self) { i in
                            section(nil, items: Self.categories[i].items.map(String.init), id: i)
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 8)
                }
            }
        }
    }

    private func categoryButton(_ icon: String, id: Int, proxy: ScrollViewProxy) -> some View {
        Button {
            Safir.tap()
            selected = id
            withAnimation(Safir.spring) { proxy.scrollTo(id, anchor: .top) }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected == id ? Safir.accent : Safir.muted)
                .frame(width: 38, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected == id ? Safir.accent.opacity(0.16) : .clear))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    /// Эмодзи | Стикеры in a sliding pill, backspace on the right while typing emoji.
    private var bottomBar: some View {
        HStack {
            Color.clear.frame(width: 44, height: 36)
            Spacer(minLength: 0)
            if onSticker != nil {
                HStack(spacing: 0) {
                    pillButton(tr("Эмодзи"), index: 0)
                    pillButton(tr("Стикеры"), index: 1)
                }
                .padding(3)
                .background(Capsule().fill(Safir.card.opacity(0.9)))
                .overlay(Capsule().stroke(Safir.separator.opacity(0.6), lineWidth: 0.5))
            }
            Spacer(minLength: 0)
            Button {
                Safir.tap()
                onBackspace()
            } label: {
                Image(systemName: "delete.left").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Safir.muted).frame(width: 44, height: 36)
            }
            .buttonStyle(.plain)
            .opacity(stickersOn ? 0 : 1)
            .disabled(stickersOn)
            .accessibilityLabel(tr("Удалить"))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func pillButton(_ title: String, index: Int) -> some View {
        let on = (stickersOn ? 1 : 0) == index
        return Button {
            guard !on else { return }
            Safir.tap()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { tab = index }
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(on ? .white : Safir.muted)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background {
                    if on {
                        Capsule().fill(Safir.brandGradient).matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(index == 0 ? "panel-emoji" : "panel-stickers")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private func section(_ title: String?, items: [String], id: Int) -> some View {
        Section {
            ForEach(Array(items.enumerated()), id: \.offset) { _, emoji in
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    onPick(emoji)
                    remember(emoji)
                } label: {
                    // Animated (Noto) where we have it: plays once when the cell shows.
                    AnimatedEmojiView(emoji: emoji, size: 34).frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(PressableStyle())
            }
        } header: {
            if let title {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Safir.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6).padding(.top, 4)
            } else {
                Color.clear.frame(height: 4)
            }
        }
        .id(id)
    }

    private func remember(_ emoji: String) {
        var list = (UserDefaults.standard.stringArray(forKey: "recent_emoji") ?? []).filter { $0 != emoji }
        list.insert(emoji, at: 0)
        // The recent row updates next time the panel opens, so the grid doesn't jump under the finger.
        UserDefaults.standard.set(Array(list.prefix(24)), forKey: "recent_emoji")
    }
}

/// The stickers tab: recently sent, the animated emoji (Noto Lottie), then Safir's drawn pack.
private struct StickerGrid: View {
    let onPick: (StickerDef) -> Void
    @State private var recent: [StickerDef] = (UserDefaults.standard.stringArray(forKey: StickerGrid.recentKey) ?? [])
        .compactMap { StickerDef.from(content: StickerDef.token($0)) }
    @State private var selected = "animated"

    static let recentKey = "recent_stickers"
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    if !recent.isEmpty { jump("clock", to: "recent", proxy) }
                    jump("sparkles", to: "animated", proxy)
                    jump("seal.fill", to: "safir", proxy)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        if !recent.isEmpty {
                            Section { ForEach(recent) { cell($0) } } header: { header(tr("Недавние")) }
                                .id("recent")
                        }
                        Section { ForEach(StickerDef.animatedPack) { cell($0) } } header: { header(tr("Анимированные")) }
                            .id("animated")
                        Section { ForEach(StickerDef.pack) { cell($0) } } header: { header("Safir") }
                            .id("safir")
                    }
                    .padding(.horizontal, 8)
                    // CC BY 4.0 asks for the credit.
                    Text("Animated emoji: Google Noto Emoji, CC BY 4.0").font(.caption2).foregroundStyle(Safir.muted)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    private func jump(_ icon: String, to id: String, _ proxy: ScrollViewProxy) -> some View {
        Button {
            Safir.tap()
            selected = id
            withAnimation(Safir.spring) { proxy.scrollTo(id, anchor: .top) }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected == id ? Safir.accent : Safir.muted)
                .frame(width: 38, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected == id ? Safir.accent.opacity(0.16) : .clear))
        }
        .buttonStyle(.plain)
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(Safir.muted)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6).padding(.top, 6)
    }

    private func cell(_ sticker: StickerDef) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onPick(sticker)
            remember(sticker.id)
        } label: {
            Group {
                if sticker.isAnimatedEmoji {
                    AnimatedEmojiView(emoji: sticker.emoji, size: 62)
                } else {
                    StickerView(sticker: sticker, size: 74)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(sticker.caption ?? sticker.emoji)
    }

    private func remember(_ id: String) {
        var list = (UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []).filter { $0 != id }
        list.insert(id, at: 0)
        // Like the emoji: the row refreshes the next time the panel opens.
        UserDefaults.standard.set(Array(list.prefix(12)), forKey: Self.recentKey)
    }
}
