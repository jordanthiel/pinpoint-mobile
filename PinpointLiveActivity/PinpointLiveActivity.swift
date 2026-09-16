import ActivityKit
import SwiftUI
import WidgetKit

private let coral = Color(red: 1, green: 0.49, blue: 0.37)

@main
struct PinpointActivityBundle: WidgetBundle {
    var body: some Widget { activities() }

    private func activities() -> some Widget {
        if #available(iOSApplicationExtension 18.0, *) {
            return AdaptivePinpointLiveActivity()
        } else {
            return PinpointLiveActivity()
        }
    }
}

@available(iOSApplicationExtension 18.0, *)
struct AdaptivePinpointLiveActivity: Widget {
    var body: some WidgetConfiguration {
        PinpointLiveActivity().body.supplementalActivityFamilies([.small, .medium])
    }
}

struct PinpointLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GolfActivityAttributes.self) { context in
            Group {
                if #available(iOSApplicationExtension 18.0, *) {
                    AdaptiveRoundActivity(context: context)
                } else {
                    RoundActivityView(context: context, small: false)
                }
            }
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "pinpoint://round/\(context.attributes.roundID.uuidString)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Hole \(context.state.hole)", systemImage: "flag.fill")
                        .font(.headline).foregroundStyle(coral)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Par \(context.state.par)").font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        ActivityYardage(context: context, size: 36)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(context.attributes.course).lineLimit(1)
                            Text("Round \(context.state.toPar) · \(context.state.holesCompleted) holes")
                                .foregroundStyle(.secondary)
                        }.font(.caption)
                    }
                }
            } compactLeading: {
                Label("\(context.state.hole)", systemImage: "flag.fill").foregroundStyle(coral)
            } compactTrailing: {
                Text(context.isStale ? "—" : context.state.yards.map { "\(context.state.estimated ? "~" : "")\($0)y" } ?? "—")
                    .monospacedDigit().foregroundStyle(.white)
            } minimal: {
                Text("\(context.state.hole)").font(.headline).foregroundStyle(coral)
            }
            .keylineTint(coral)
            .widgetURL(URL(string: "pinpoint://round/\(context.attributes.roundID.uuidString)"))
        }
    }
}

@available(iOSApplicationExtension 18.0, *)
private struct AdaptiveRoundActivity: View {
    @Environment(\.activityFamily) private var family
    let context: ActivityViewContext<GolfActivityAttributes>
    var body: some View { RoundActivityView(context: context, small: family == .small) }
}

private struct RoundActivityView: View {
    let context: ActivityViewContext<GolfActivityAttributes>
    let small: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: small ? 6 : 12) {
            HStack {
                Label("Hole \(context.state.hole)", systemImage: "flag.fill")
                    .foregroundStyle(coral).font(.headline)
                Spacer(minLength: 4)
                Text("Par \(context.state.par)").font(.subheadline)
            }
            HStack(alignment: .center) {
                ActivityYardage(context: context, size: small ? 34 : 44)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(context.state.score.map(String.init) ?? "—")
                        .font(.system(size: small ? 24 : 30, weight: .semibold)).monospacedDigit()
                    Text("Score").font(.caption).foregroundStyle(.white.opacity(0.65))
                }
            }
            if !small {
                HStack {
                    Text(context.attributes.course).lineLimit(1)
                    Spacer()
                    Text("\(context.state.toPar) · \(context.state.holesCompleted) holes").fixedSize()
                }.font(.caption).foregroundStyle(.white.opacity(0.65))
            }
        }
        .foregroundStyle(.white)
        .padding(small ? 12 : 16)
        .minimumScaleFactor(0.75)
    }
}

private struct ActivityYardage: View {
    let context: ActivityViewContext<GolfActivityAttributes>
    let size: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(context.isStale ? "—" : context.state.yards.map(String.init) ?? "—")
                    .font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit()
                Text("yd").font(.caption)
            }
            Text(context.isStale ? "Open app to refresh" : context.state.estimated ? "Estimated to pin" : "To pin")
                .font(.caption2).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
        }.accessibilityElement(children: .combine)
    }
}
