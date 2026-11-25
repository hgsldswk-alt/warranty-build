import SwiftUI

enum Theme {
    static let accent = color(0x48515A)
    static let accentSoft = color(0xE8ECEF)
    static let background = color(0xF6F4EF)
    static let paper = Color.white
    static let ink = color(0x1F2731)
    static let muted = color(0x5B6470)
    static let line = color(0xE3DFD6)
    static let camera = color(0x20262D)
    static let shareBack = color(0x343B43)

    static let mint = color(0x5FB39A)
    static let due = color(0xE3A33B)
    static let blue = color(0x7FA7C9)
    static let dueText = color(0x6B3D12)

    static let radius: CGFloat = 18
    static let sectionSpacing: CGFloat = 22
    static let pageInset: CGFloat = 18

    static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255
        )
    }
}

enum AccentTone {
    case slate, mint, amber, blue

    var color: Color {
        switch self {
        case .slate: return Theme.accent
        case .mint: return Theme.mint
        case .amber: return Theme.due
        case .blue: return Theme.blue
        }
    }

    var soft: Color {
        switch self {
        case .slate: return Theme.accentSoft
        case .mint: return Theme.color(0xE3F2EC)
        case .amber: return Theme.color(0xFBEDD5)
        case .blue: return Theme.color(0xE5EFF6)
        }
    }

    var ink: Color {
        switch self {
        case .slate: return Theme.accent
        case .mint: return Theme.color(0x245E4D)
        case .amber: return Theme.dueText
        case .blue: return Theme.color(0x315573)
        }
    }

    static func deadline(days: Int) -> Self {
        if days < 0 { return .blue }
        return days <= 14 ? .amber : .mint
    }
}

struct CategoryMark {
    let icon: String
    let tone: AccentTone

    init(_ category: String) {
        let mark: (icon: String, tone: AccentTone)
        switch category {
        case "appliance": mark = ("washer.fill", .mint)
        case "electronics": mark = ("desktopcomputer", .blue)
        case "furniture": mark = ("chair.lounge.fill", .amber)
        case "car": mark = ("car.fill", .amber)
        case "tools": mark = ("wrench.and.screwdriver.fill", .mint)
        case "document": mark = ("person.text.rectangle.fill", .blue)
        default: mark = ("tray.fill", .slate)
        }
        icon = mark.icon
        tone = mark.tone
    }
}

extension View {
    func testID(_ id: String) -> some View { accessibilityIdentifier(id) }

    func cardSurface() -> some View {
        background {
            RoundedRectangle(cornerRadius: Theme.radius)
                .fill(Theme.paper)
                .shadow(color: Theme.ink.opacity(0.07), radius: 12, x: 0, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(Theme.line.opacity(0.7))
                .allowsHitTesting(false)
        }
        .foregroundStyle(Theme.ink)
    }

    func card() -> some View { padding(14).cardSurface() }

    func secondaryControl() -> some View {
        font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(Theme.accent)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
    }
}

struct SectionHeading: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Theme.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

struct HeroCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: Theme.radius)
                    .fill(LinearGradient(
                        colors: [Theme.color(0xD6DFE6), Theme.color(0xF3F5F6)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .shadow(color: Theme.ink.opacity(0.07), radius: 12, x: 0, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(.white.opacity(0.8))
                    .allowsHitTesting(false)
            }
            .foregroundStyle(Theme.ink)
    }
}

struct IconGlyph: View {
    var icon: String
    var tone: AccentTone
    var size: CGFloat = 38
    var circular = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tone.ink)
            .frame(width: size, height: size)
            .background(tone.soft, in: RoundedRectangle(cornerRadius: circular ? size / 2 : 11))
            .accessibilityHidden(true)
    }
}

struct IconTile: View {
    var title: String
    var icon: String
    var tone: AccentTone

    var body: some View {
        HStack(spacing: 8) {
            IconGlyph(icon: icon, tone: tone, size: 30, circular: true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 48)
        .cardSurface()
        .contentShape(Rectangle())
    }
}

struct IconRow<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    var icon: String
    var tone: AccentTone
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            IconGlyph(icon: icon, tone: tone)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct StatusPill: View {
    var title: String
    var tone: AccentTone
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).accessibilityHidden(true) }
            Text(title).monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tone.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tone.soft, in: Capsule())
    }
}

struct ProgressCapsule: View {
    var value: Double
    var tone: AccentTone

    var body: some View {
        let fraction = min(1, max(0, value))
        GeometryReader { proxy in
            Capsule().fill(Theme.accent.opacity(0.14))
                .overlay(alignment: .leading) {
                    Capsule().fill(tone.color)
                        .frame(width: proxy.size.width * CGFloat(fraction))
                }
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("design.elapsed"))
        .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
    }
}

struct ReceiptIllustration: View {
    var tone: AccentTone = .mint
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            Circle().fill(tone.soft)
            Image(systemName: "receipt.fill")
                .font(.system(size: size * 0.49, weight: .medium))
                .foregroundStyle(Theme.accent)
                .rotationEffect(.degrees(-10))
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: size * 0.25, weight: .semibold))
                .foregroundStyle(.white, tone.ink)
                .offset(x: size * 0.32, y: size * 0.27)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct EmptyIllustration: View {
    var icon = "receipt.fill"
    var size: CGFloat = 108

    var body: some View {
        ZStack {
            Circle().fill(Theme.accentSoft).frame(width: size * 0.7, height: size * 0.7)
            Image(systemName: "folder.fill")
                .font(.system(size: size * 0.43))
                .foregroundStyle(Theme.blue)
                .rotationEffect(.degrees(-18))
                .offset(x: -size * 0.25, y: size * 0.08)
            Image(systemName: icon)
                .font(.system(size: size * 0.41, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .rotationEffect(.degrees(9))
                .offset(x: size * 0.10, y: -size * 0.04)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: size * 0.23, weight: .semibold))
                .foregroundStyle(.white, AccentTone.mint.ink)
                .offset(x: size * 0.32, y: size * 0.24)
        }
        .frame(width: size, height: size * 0.77)
        .accessibilityHidden(true)
    }
}

struct PrimaryButtonLabel: View {
    var title: String
    var icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
    }
}

struct PrimaryButton: View {
    @Environment(\.isEnabled) private var isEnabled
    var title: String
    var id: String
    var icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) { PrimaryButtonLabel(title: title, icon: icon).opacity(isEnabled ? 1 : 0.56) }
            .buttonStyle(.plain).testID(id)
    }
}

struct SecondaryButton: View {
    @Environment(\.isEnabled) private var isEnabled
    var title: String
    var id: String
    var icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).secondaryControl().opacity(isEnabled ? 1 : 0.56)
        }
        .buttonStyle(.plain).testID(id)
    }
}
