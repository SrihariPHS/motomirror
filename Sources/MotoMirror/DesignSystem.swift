import AppKit
import SwiftUI

// MARK: - Palette

enum MMTheme {
    static let indigo = Color(red: 0.35, green: 0.38, blue: 0.86)
    static let indigoDeep = Color(red: 0.24, green: 0.27, blue: 0.70)
    static let teal = Color(red: 0.08, green: 0.58, blue: 0.58)
    static let green = Color(red: 0.16, green: 0.65, blue: 0.40)
    static let orange = Color(red: 0.90, green: 0.55, blue: 0.10)
    static let red = Color(red: 0.84, green: 0.24, blue: 0.24)
    static let blue = Color(red: 0.24, green: 0.50, blue: 0.91)
    static let gray = Color(red: 0.52, green: 0.54, blue: 0.60)

    static let cardRadius: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let pagePadding: CGFloat = 26

    static var cardFill: Color { Color(nsColor: .controlBackgroundColor) }
    static var pageFill: Color { Color(nsColor: .windowBackgroundColor) }
    static var insetFill: Color { Color(nsColor: .textBackgroundColor) }
    static var sidebarFill: Color { Color(nsColor: .underPageBackgroundColor) }

    static let brandGradient = LinearGradient(
        colors: [indigo, teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func batteryColor(level: Int?) -> Color {
        guard let level else { return gray }
        if level <= 15 { return red }
        if level <= 40 { return orange }
        return green
    }
}

// MARK: - App mark

struct AppMark: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(MMTheme.brandGradient)
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: MMTheme.indigo.opacity(0.28), radius: 7, y: 3)
        .accessibilityHidden(true)
    }
}

// MARK: - Cards

private struct CardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: MMTheme.cardRadius, style: .continuous)
        content
            .padding(padding)
            .background(shape.fill(MMTheme.cardFill))
            .overlay(
                shape.strokeBorder(
                    Color.primary.opacity(colorScheme == .dark ? 0.13 : 0.07),
                    lineWidth: 1
                )
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.20 : 0.035),
                radius: 9,
                y: 3
            )
    }
}

extension View {
    func mmCard(padding: CGFloat = MMTheme.cardPadding) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

// MARK: - Status pill

struct StatusPill: View {
    let text: String
    var tint: Color = MMTheme.green
    var icon: String?
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: compact ? 9 : 10, weight: .bold))
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
            }
            Text(text)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 3 : 5)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct StateDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(color.opacity(0.35), lineWidth: 3).padding(-3))
            .accessibilityHidden(true)
    }
}

// MARK: - Headers

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var trailing: AnyView?

    init(title: String, subtitle: String? = nil, icon: String? = nil, trailing: AnyView? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MMTheme.indigo)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let trailing { trailing }
        }
    }
}

// MARK: - Buttons

struct MMPrimaryButtonStyle: ButtonStyle {
    var tint: Color = MMTheme.indigo
    var large = false
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: large ? 12 : 8, style: .continuous)
        configuration.label
            .font(.system(size: large ? 15 : 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 22 : 13)
            .frame(height: large ? 50 : 30)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.82)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .shadow(
                color: tint.opacity(isEnabled ? 0.28 : 0),
                radius: 6,
                y: 2
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.42)
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MMSecondaryButtonStyle: ButtonStyle {
    var tint: Color = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.11 : 0.055)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.42)
    }
}

struct MMQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.09 : 0.04))
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct MMIconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.045))
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - Meters and tiles

struct MeterBar: View {
    let fraction: Double
    var tint: Color = MMTheme.indigo
    var height: CGFloat = 9

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.075))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.62)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct MetricTile: View {
    let icon: String
    let title: String
    let value: String
    var caption: String?
    var tint: Color = MMTheme.indigo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .accessibilityElement(children: .combine)
    }
}

struct NumberedStep: View {
    let number: Int
    let title: String
    let detail: String
    var icon: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(MMTheme.indigo.opacity(0.12))
                    .frame(width: 26, height: 26)
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(MMTheme.indigo)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Backgrounds

struct PageBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MMTheme.pageFill
            RadialGradient(
                colors: [
                    MMTheme.indigo.opacity(colorScheme == .dark ? 0.13 : 0.055),
                    .clear
                ],
                center: .topLeading,
                startRadius: 10,
                endRadius: 720
            )
            RadialGradient(
                colors: [
                    MMTheme.teal.opacity(colorScheme == .dark ? 0.07 : 0.03),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 620
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Snapshot layout

private struct MMSnapshotLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Snapshot rendering cannot use `List` or `ScrollView`, so views swap in
    /// flat stacks when this flag is set. The live app leaves it false.
    var mmSnapshotLayout: Bool {
        get { self[MMSnapshotLayoutKey.self] }
        set { self[MMSnapshotLayoutKey.self] = newValue }
    }
}

struct DetailScroll<Content: View>: View {
    @Environment(\.mmSnapshotLayout) private var isSnapshot
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if isSnapshot {
            GeometryReader { proxy in
                content
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .topLeading
                    )
                    .clipped()
            }
        } else {
            ScrollView {
                content
            }
        }
    }
}

// MARK: - Formatting

enum MMFormat {    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
    }

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    static func sessionTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: date)
    }
}
