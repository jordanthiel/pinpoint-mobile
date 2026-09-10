import SwiftUI

/// Live GPS hole view: schematic map, caddie pill, shot trail, hole pager,
/// score chip, and actions (add shot, dictate, green, scorecard, next hole).
struct ActiveRoundView: View {
    @Environment(RoundStore.self) private var rounds

    @State private var selectedHole: Int?
    @State private var showShotEditor = false
    @State private var editingShot: TrackedShot?
    @State private var showDictation = false
    @State private var showScorecard = false
    @State private var showGreen = false
    @State private var showFinishConfirm = false
    @State private var showTools = false

    var body: some View {
        Group {
            if let round = rounds.activeRound {
                content(round: round)
            } else {
                Text("No active round.")
                    .foregroundStyle(PinpointTheme.secondaryText)
            }
        }
        .background(PinpointTheme.background.ignoresSafeArea())
        .navigationTitle("On Course")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(round: GolfRound) -> some View {
        let holeNum = selectedHole ?? round.currentHoleNumber
        let holeDef = round.hole(holeNum)
        let hole = round.score(for: holeNum)
        return VStack(spacing: 0) {
            HolePickerBar(holes: round.holeScores.map(\.holeNumber), current: holeNum) { n in
                selectedHole = n
                rounds.setCurrentHole(n)
            }
            ScrollView {
                VStack(spacing: 12) {
                    if let def = holeDef, let hs = hole {
                        headerRow(round: round, holeNumber: holeNum, def: def, hole: hs)
                        HoleMapView(hole: def, shots: hs.shots,
                                    remainingYards: rounds.ballState(holeNum).distanceYards,
                                    pinX: hs.pinPosition.x, pinY: hs.pinPosition.y)
                            .frame(height: 380)
                            .padding(.horizontal, 16)
                        caddiePill(round: round, holeNumber: holeNum, def: def)
                        shotTrailList(holeNumber: holeNum, def: def, hole: hs)
                    }
                }
                .padding(.bottom, 12)
            }
            bottomBar(round: round, holeNumber: holeNum)
        }
        .sheet(isPresented: $showShotEditor) {
            if let def = holeDef {
                ShotEditorView(holeNumber: holeNum, holeYardage: def.yardage,
                               existing: editingShot, onDone: {
                                   editingShot = nil
                               })
                    .preferredColorScheme(.dark)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showDictation) {
            HoleDictationView(holeNumber: holeNum)
                .preferredColorScheme(.dark)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showScorecard) {
            ScorecardView()
                .preferredColorScheme(.dark)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGreen) {
            NavigationStack {
                if let hs = rounds.activeRound?.score(for: holeNum) {
                    GreenView(holeNumber: holeNum, pinX: hs.pinPosition.x, pinY: hs.pinPosition.y,
                              firstPuttFeet: hs.firstPuttFeet,
                              onMovePin: { x, y in
                                  rounds.updateHole(holeNum) { $0.pinPosition = .init(x: x, y: y) }
                              },
                              onConfirmPutt: { feet in
                                  rounds.updateHole(holeNum) { $0.firstPuttFeet = feet }
                                  showGreen = false
                              },
                              onSkip: { showGreen = false })
                        .padding(16)
                        .background(PinpointTheme.background)
                        .navigationTitle("Hole \(holeNum) Green")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Tools", isPresented: $showTools, titleVisibility: .visible) {
            Button("Dictate this hole") { showDictation = true }
            Button("Read the green") { showGreen = true }
            Button("View scorecard") { showScorecard = true }
            Button("Finish round", role: .destructive) { showFinishConfirm = true }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Finish round?", isPresented: $showFinishConfirm) {
            Button("Finish", role: .destructive) { rounds.finishRound() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your scorecard and stats will be saved to history.")
        }
        .onAppear {
            if selectedHole == nil { selectedHole = round.currentHoleNumber }
        }
    }

    // MARK: - Sections

    private func headerRow(round: GolfRound, holeNumber: Int, def: GolfHole, hole: HoleScore) -> some View {
        let ball = rounds.ballState(holeNumber)
        return VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hole \(holeNumber)")
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                    Text("Par \(def.par) · \(def.yardage) yds · Hcp \(def.handicap)")
                        .font(.subheadline)
                        .foregroundStyle(PinpointTheme.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(ball.distanceYards))")
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                    + Text(" Yds")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PinpointTheme.secondaryText)
                    Text(ball.distanceYards < 30 ? "to pin" : "to green")
                        .font(.caption)
                        .foregroundStyle(PinpointTheme.secondaryText)
                }
            }
            HStack(spacing: 8) {
                scoreChip(title: "Score", value: hole.hasScore ? "\(hole.grossScore)" : "–")
                scoreChip(title: "Shot", value: "\(max(1, hole.shots.count))")
                scoreChip(title: "Putt", value: "\(hole.putts)")
                Spacer()
                WindBadge(mph: round.windMph, fromDegrees: round.windFromDegrees)
            }
        }
        .padding(.horizontal, 16)
    }

    private func scoreChip(title: String, value: String) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PinpointTheme.secondaryText)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .foregroundStyle(.white)
    }

    private func caddiePill(round: GolfRound, holeNumber: Int, def: GolfHole) -> some View {
        let ball = rounds.ballState(holeNumber)
        let helping = cos(Double(holeNumber) * 0.7) // stand-in for hole-vs-wind geometry
        let playsLike = CaddieEngine.playsLike(yards: ball.distanceYards, windMph: round.windMph,
                                               windHelping: helping)
        let rec = CaddieEngine.recommendClub(for: playsLike, averages: rounds.clubAverages())
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(.black.opacity(0.7)).frame(width: 56, height: 56)
                Text("\(Int(ball.distanceYards))")
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                + Text("y")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Plays Like")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PinpointTheme.secondaryText)
                Text(CaddieEngine.adviceLine(yards: ball.distanceYards, playsLike: playsLike, recommendation: rec))
                    .font(.headline)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(PinpointTheme.secondaryText)
        }
        .padding(12)
        .background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func shotTrailList(holeNumber: Int, def: GolfHole, hole: HoleScore) -> some View {
        PlayUI.card {
            HStack {
                Text("Shots · Hole \(holeNumber)")
                    .font(.headline)
                Spacer()
                pendingWatchBadge(holeNumber: holeNumber)
                Button {
                    editingShot = nil
                    showShotEditor = true
                } label: {
                    Label("Add shot", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PinpointTheme.accent)
                }
            }
            if hole.shots.isEmpty {
                Text("No shots yet. Add your tee shot, claim a watch detection, or dictate the hole at the green.")
                    .font(.subheadline)
                    .foregroundStyle(PinpointTheme.secondaryText)
            }
            ForEach(hole.shots) { shot in
                Button {
                    editingShot = shot
                    showShotEditor = true
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(shot.isPutt ? .green.opacity(0.25) : PinpointTheme.accent.opacity(0.2))
                                .frame(width: 34, height: 34)
                            Text("\(shot.number)")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shot.club?.displayName ?? "No club")
                                .font(.subheadline.weight(.semibold))
                            Text(shotMeta(shot))
                                .font(.caption)
                                .foregroundStyle(PinpointTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: shot.source.systemImage)
                            .font(.caption)
                            .foregroundStyle(PinpointTheme.secondaryText)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(PinpointTheme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                Divider().background(PinpointTheme.hairline)
            }
        }
        .padding(.horizontal, 16)
    }

    private func shotMeta(_ shot: TrackedShot) -> String {
        var bits = [shot.lie.label]
        if let c = shot.carryYards { bits.append("\(Int(c)) yds") }
        else if let d = shot.distanceToPinBeforeYards { bits.append("\(Int(d)) to pin") }
        if let s = shot.shape, s != .straight { bits.append(s.label) }
        if let c = shot.contact, c != .pure { bits.append(c.label) }
        return bits.joined(separator: " · ")
    }

    private func pendingWatchBadge(holeNumber: Int) -> some View {
        let n = rounds.watchDetector.unclaimedCount
        return Group {
            if n > 0 {
                NavigationLink {
                    WatchInboxView(holeNumber: holeNumber)
                } label: {
                    Label("\(n) watch", systemImage: "applewatch")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.orange, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bottomBar(round: GolfRound, holeNumber: Int) -> some View {
        let order = round.holeScores.map(\.holeNumber)
        let idx = order.firstIndex(of: holeNumber) ?? 0
        let isLast = idx == order.count - 1
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    showDictation = true
                } label: {
                    Label("Dictate", systemImage: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                Button {
                    showScorecard = true
                } label: {
                    Text("Edit Score")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                Button {
                    showTools = true
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 52)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Button {
                rounds.updateHole(holeNumber) { $0.isComplete = true }
                if !isLast {
                    let next = order[idx + 1]
                    selectedHole = next
                    rounds.setCurrentHole(next)
                } else {
                    showScorecard = true
                }
            } label: {
                Text(isLast ? "Review Scorecard" : "Go to Next Hole")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .background(PinpointTheme.background)
    }
}
