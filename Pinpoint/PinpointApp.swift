import SwiftUI

@main
struct PinpointApp: App {
    @State private var library = SwingLibraryStore()
    @State private var rounds = PinpointRuntime.shared.rounds
    @State private var golfSync = PinpointRuntime.shared.golfSync
    @Environment(\.scenePhase) private var scenePhase
    #if PINPOINT_CARPLAY
    @UIApplicationDelegateAdaptor(CarPlayAppDelegate.self) private var carPlayDelegate
    #else
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var phoneDelegate
    #endif

    @ViewBuilder private var launchView: some View {
        #if DEBUG
        if CommandLine.arguments.contains("--ui-round-review") {
            NavigationStack {
                RoundSummaryView(selectedRoundID: rounds.pastRounds.first?.id)
            }.task {
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("round-review-fixture.json")
                if let bytes = try? Data(contentsOf: url),
                   let checkpoint = try? JSONDecoder().decode(GolfRecordCheckpoint.self, from: bytes) {
                    let data = GolfRecords.assembleTolerant(checkpoint.records).state
                    _ = rounds.applyCloud(data, revision: checkpoint.cursor, base: data)
                }
            }
        } else { ContentView() }
        #else
        ContentView()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            launchView
                .task { PhoneCompanionSession.shared.start(rounds: rounds) }
                .task { await golfSync.observeAccount() }
                .task {
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                        if scenePhase == .active {
                            RoundLiveActivity.shared.refresh(rounds: rounds)
                            // Retry unsent edits after connectivity returns;
                            // acknowledged history is fetched only on request.
                            if rounds.pendingUpload != nil || rounds.cloudData != rounds.cloudBase { await golfSync.sync() }
                        }
                    }
                }
                .onChange(of: scenePhase) { _, phase in if phase == .active {
                    RoundLiveActivity.shared.refresh(rounds: rounds)
                    Task { await golfSync.sync() }
                } }
                .environment(golfSync)
                .environment(library)
                .environment(rounds)
                .preferredColorScheme(.light)
                .tint(PinpointTheme.primaryText)
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
        .preferredColorScheme(.light)
}

@MainActor
final class PinpointRuntime {
    static let shared = PinpointRuntime()
    let rounds = RoundStore()
    lazy var golfSync = GolfCloudSync(store: rounds)
}
