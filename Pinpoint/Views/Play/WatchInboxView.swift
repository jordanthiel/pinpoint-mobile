import SwiftUI

/// Watch detection inbox: pending motion+sound strikes waiting for a club
/// and lie. Claiming one adds a real shot to the given hole.
struct WatchInboxView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    /// Hole to attach claimed shots to. Defaults to the active hole.
    var holeNumber: Int?

    @State private var claiming: WatchShotEvent?
    @State private var claimClub: GolfClub = .iron7
    @State private var claimLie: Lie = .fairway

    var body: some View {
        ZStack {
            PinpointTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusCard
                    if rounds.watchDetector.pendingEvents.isEmpty {
                        emptyState
                    } else {
                        ForEach(rounds.watchDetector.pendingEvents) { event in
                            eventRow(event)
                        }
                        Button("Clear claimed") {
                            rounds.watchDetector.clearClaimed()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PinpointTheme.accent)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Watch Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $claiming) { event in
            claimSheet(event)
                .preferredColorScheme(.dark)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var targetHole: Int {
        holeNumber ?? rounds.activeRound?.currentHoleNumber ?? 1
    }

    private var statusCard: some View {
        PlayUI.card {
            HStack {
                Image(systemName: rounds.watchDetector.isListening ? "applewatch.radiowaves.left.and.right" : "applewatch")
                    .font(.title2)
                    .foregroundStyle(PinpointTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rounds.watchDetector.isListening ? "Listening for strikes" : "Detection paused")
                        .font(.headline)
                    Text(watchDetail)
                        .font(.caption)
                        .foregroundStyle(PinpointTheme.secondaryText)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button(rounds.watchDetector.isListening ? "Stop" : "Start listening") {
                    rounds.watchDetector.isListening
                        ? rounds.watchDetector.stopListening()
                        : rounds.watchDetector.startListening()
                    if let err = rounds.watchDetector.lastError {
                        rounds.lastError = err
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Simulate swing") {
                    rounds.watchDetector.simulateShot()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            if let err = rounds.watchDetector.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var watchDetail: String {
        var bits: [String] = ["Motion + impact sound fusion"]
        #if canImport(WatchConnectivity)
        bits.append(rounds.watchDetector.watchReachable ? "Watch reachable" : "Watch not reachable")
        #endif
        return bits.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "applewatch")
                .font(.system(size: 44))
                .foregroundStyle(PinpointTheme.accent)
            Text("No swings detected yet")
                .font(.headline)
            Text("Swing with your phone in your pocket (or a paired watch) and strikes appear here. Nothing is added to your card until you claim it.")
                .font(.subheadline)
                .foregroundStyle(PinpointTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func eventRow(_ event: WatchShotEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.source == "watch" ? "applewatch" : event.source == "simulated" ? "wand.and.stars" : "iphone")
                .foregroundStyle(PinpointTheme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.isLikelyStrike ? "Likely strike" : "Possible swing")
                    .font(.subheadline.weight(.semibold))
                Text("\(String(format: "%.1f", event.peakAccelerationG))g · +\(Int(event.audioJumpDb))dB · \(Int(event.confidence * 100))% · \(event.timestamp.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(PinpointTheme.secondaryText)
            }
            Spacer()
            if event.claimed {
                Text("Added")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
            } else {
                Button("Claim") {
                    claimClub = .iron7
                    claimLie = rounds.ballState(targetHole).lie
                    claiming = event
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(PinpointTheme.accent, in: Capsule())
                .buttonStyle(.plain)
                Button {
                    rounds.watchDetector.remove(event)
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(PinpointTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func claimSheet(_ event: WatchShotEvent) -> some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Add to Hole \(targetHole) as…")
                        .font(.headline)
                    Text("Club").font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(GolfClub.allCases) { c in
                                Button {
                                    claimClub = c
                                } label: {
                                    Text(c.shortName)
                                        .font(.subheadline.weight(.bold))
                                        .frame(minWidth: 48)
                                        .padding(.vertical, 8)
                                        .background(claimClub == c ? PinpointTheme.accent : PinpointTheme.surfaceElevated,
                                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .foregroundStyle(claimClub == c ? .white : PinpointTheme.secondaryText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Text("Lie").font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Lie.allCases) { l in
                                Button {
                                    claimLie = l
                                } label: {
                                    Text(l.label)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(claimLie == l ? PinpointTheme.accent.opacity(0.25) : PinpointTheme.surfaceElevated,
                                                    in: Capsule())
                                        .foregroundStyle(claimLie == l ? PinpointTheme.accent : .white)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button {
                        let ball = rounds.ballState(targetHole)
                        let shot = TrackedShot(
                            number: rounds.nextShotNumber(targetHole),
                            club: claimClub, lie: claimLie,
                            distanceToPinBeforeYards: ball.distanceYards,
                            carryYards: claimClub.isPutter ? nil : claimClub.stockYards,
                            source: .watch, timestamp: event.timestamp
                        )
                        if rounds.activeRound != nil {
                            rounds.addShot(targetHole, shot)
                        }
                        rounds.watchDetector.claim(event)
                        claiming = nil
                    } label: {
                        Text("Add shot to Hole \(targetHole)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Claim Swing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { claiming = nil }
                }
            }
        }
    }
}
