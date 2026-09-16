import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PinpointTheme.TypeStyle.label)
            .frame(minHeight: 24)
            .padding(.horizontal, 22).padding(.vertical, 14)
            .foregroundStyle(PinpointTheme.onDark)
            .background(PinpointTheme.primaryText, in: Capsule())
            .shadow(color: .black.opacity(enabled ? 0.10 : 0), radius: 9, y: 4)
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.38)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PinpointTheme.TypeStyle.label)
            .frame(minHeight: 24)
            .padding(.horizontal, 22).padding(.vertical, 14)
            .foregroundStyle(PinpointTheme.primaryText)
            .background(PinpointTheme.surfaceElevated, in: Capsule())
            .overlay(Capsule().stroke(PinpointTheme.hairline, lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.38)
    }
}

struct PinpointIconButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 18, weight: .medium))
            .frame(width: 46, height: 46)
            .foregroundStyle(prominent ? PinpointTheme.onDark : PinpointTheme.primaryText)
            .background(prominent ? PinpointTheme.primaryText : PinpointTheme.surface, in: Circle())
            .overlay(Circle().stroke(PinpointTheme.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension View {
    func pinpointCard() -> some View {
        background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: PinpointTheme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: PinpointTheme.Radius.card).stroke(PinpointTheme.hairline, lineWidth: 0.7))
            .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
    }
    func pinpointField() -> some View {
        padding(14).background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: PinpointTheme.Radius.field))
            .foregroundStyle(PinpointTheme.primaryText)
    }
}

struct PinpointPageHeading: View {
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(PinpointTheme.TypeStyle.hero).foregroundStyle(PinpointTheme.primaryText)
            Text(subtitle).font(.subheadline).foregroundStyle(PinpointTheme.secondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PinpointNavigationRow: View {
    var title: String
    var subtitle: String = ""
    var symbol: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 20, weight: .regular)).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(PinpointTheme.TypeStyle.label)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(PinpointTheme.secondaryText) }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.medium))
        }.foregroundStyle(PinpointTheme.primaryText).padding(18).frame(minHeight: 64).pinpointCard()
    }
}

/// Screens with immersive maps or video suppress the floating root navigation.
struct PinpointImmersiveKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

#Preview("Brand components") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            PinpointPageHeading(title: "Your game.\nA little clearer.", subtitle: "Pinpoint design system")
            PlayUI.card {
                Text("Your next round").font(PinpointTheme.TypeStyle.section)
                HStack { StatTile(title: "Holes", value: "18"); StatTile(title: "Par", value: "72") }
                Button("Continue round") {}.buttonStyle(PrimaryButtonStyle())
                Button("View scorecard") {}.buttonStyle(SecondaryButtonStyle())
            }
            PinpointNavigationRow(title: "Your bag", subtitle: "Clubs and measured carries", symbol: "bag")
            Text("A form field").pinpointField()
        }.padding(20)
    }.background(PinpointTheme.background).preferredColorScheme(.light)
}

/// Space to scroll the final control above the floating capsule, without a footer fill.
enum FloatingNavigation {
    static let clearance: CGFloat = 66
}
