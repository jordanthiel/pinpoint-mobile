import SwiftUI

@main
struct PinpointApp: App {
    @State private var library = SwingLibraryStore()
    @State private var rounds = RoundStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(rounds)
                .preferredColorScheme(.dark)
                .tint(PinpointTheme.accent)
        }
    }
}

struct ContentView: View {
    @Environment(RoundStore.self) private var rounds
    @State private var ready = false

    private static var isHoleProbe: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("--ui-hole-") }
    }

    var body: some View {
        if Self.isHoleProbe {
            Group {
                if ready {
                    NavigationStack { ActiveRoundView() }
                } else {
                    Color.black
                }
            }
            .task {
                rounds.discardActiveRound()
                rounds.startRound(
                    course: SampleCourses.georgetown,
                    teeName: "Blue",
                    roundType: .eighteen,
                    scoringMode: .smart,
                    startHole: 1
                )
                ready = true
            }
        } else {
            MainTabView()
        }
    }
}

#Preview {
    ContentView()
        .environment(SwingLibraryStore())
        .environment(RoundStore())
        .preferredColorScheme(.dark)
}
