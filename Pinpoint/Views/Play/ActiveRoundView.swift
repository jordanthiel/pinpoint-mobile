import MapKit
import SwiftUI

/// Live GPS hole view: satellite map, drag-to-measure distances, shot trail,
/// pin edit, and 18Birdies-style score / next-hole chrome.
struct ActiveRoundView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    @State private var selectedHole: Int?
    @State private var showShotEditor = false
    @State private var editingShot: TrackedShot?
    @State private var pendingMeasure: GeoPoint?
    @State private var showDictation = false
    @State private var showScorecard = false
    @State private var showGreen = false
    @State private var greenMode: GreenView.Mode = .pin
    @State private var showFinishConfirm = false
    @State private var showTools = false
    @State private var showWatch = false
    @State private var showHolePicker = false
    @State private var measurePoint: GeoPoint?
    @State private var hoverPoint: GeoPoint?
    @State private var cameraPosition: MapCameraPosition =
        GeorgetownGPS.layout(for: 1)?.cameraPosition() ?? .automatic
    @State private var location = PlayerLocation()

    var body: some View {
        Group {
            if let round = rounds.activeRound {
                content(round: round)
            } else {
                Text("No active round.")
                    .foregroundStyle(PinpointTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PinpointTheme.background)
            }
        }
        .background(PinpointTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            location.start()
            if selectedHole == nil, let round = rounds.activeRound {
                selectedHole = round.currentHoleNumber
                if let layout = round.layout(for: round.currentHoleNumber) {
                    cameraPosition = layout.cameraPosition(pin: round.pinCoordinate(for: round.currentHoleNumber))
                }
            }
        }
        .onDisappear { location.stop() }
    }

    private func content(round: GolfRound) -> some View {
        let holeNum = selectedHole ?? round.currentHoleNumber
        let holeDef = round.hole(holeNum)
        let hole = round.score(for: holeNum)
        let layout = round.layout(for: holeNum)
        let pin = round.pinCoordinate(for: holeNum) ?? layout?.pin
        let ball = liveBall(round: round, holeNumber: holeNum)
        let onThisHole = location.coordinate.map { GeorgetownGPS.isStanding(on: holeNum, at: $0) } ?? false

        return ZStack {
            if let layout, let pin, let holeDef, let hole {
                HoleMapView(
                    position: $cameraPosition,
                    layout: layout,
                    pin: pin,
                    ball: ball,
                    shots: hole.shots,
                    measurePoint: measurePoint,
                    hoverPoint: hoverPoint,
                    showsUserLocation: onThisHole,
                    showsGreenDistances: hole.shots.isEmpty,
                    putts: hole.putts,
                    firstPuttFeet: hole.firstPuttFeet,
                    onTapCoordinate: { measurePoint = $0 },
                    onHoverCoordinate: { hoverPoint = $0 },
                    onSelectShot: { shot in
                        editingShot = shot
                        pendingMeasure = nil
                        showShotEditor = true
                    }
                )
                .ignoresSafeArea()

                gpsChrome(round: round, holeNumber: holeNum, def: holeDef, hole: hole,
                          layout: layout, pin: pin, ball: ball, onThisHole: onThisHole)
            } else {
                Color.black.ignoresSafeArea()
                Text("No GPS layout for this hole.")
                    .foregroundStyle(.white)
            }
        }
        .sheet(isPresented: $showShotEditor) {
            if let def = holeDef {
                ShotEditorView(
                    holeNumber: holeNum,
                    holeYardage: def.yardage,
                    existing: editingShot,
                    prefillStart: rounds.activeRound?.ballCoordinate(for: holeNum),
                    prefillEnd: pendingMeasure,
                    onDone: {
                        editingShot = nil
                        pendingMeasure = nil
                        measurePoint = nil
                    }
                )
                .preferredColorScheme(.dark)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showWatch) {
            NavigationStack {
                WatchInboxView(holeNumber: holeNum)
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showDictation) {
            HoleDictationView(holeNumber: holeNum)
                .preferredColorScheme(.dark)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showScorecard) {
            ScorecardView()
                .preferredColorScheme(.dark)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGreen) {
            if let layout {
                GreenView(
                    holeNumber: holeNum,
                    mode: greenMode,
                    layout: layout,
                    pin: pin ?? layout.pin,
                    firstPuttFeet: hole?.firstPuttFeet,
                    onMovePin: { geo in
                        rounds.updateHole(holeNum) {
                            $0.pinPosition.latitude = geo.latitude
                            $0.pinPosition.longitude = geo.longitude
                        }
                    },
                    onConfirmPutt: { feet in
                        rounds.updateHole(holeNum) { $0.firstPuttFeet = feet }
                        showGreen = false
                    },
                    onSkip: { showGreen = false }
                )
                .preferredColorScheme(.dark)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog("Tools", isPresented: $showTools, titleVisibility: .visible) {
            Button("Add shot") { openNewShot(at: measurePoint) }
            if rounds.watchDetector.unclaimedCount > 0 {
                Button("Watch shots (\(rounds.watchDetector.unclaimedCount))") { showWatch = true }
            }
            Button("Dictate this hole") { showDictation = true }
            Button("Confirm 1st putt") {
                greenMode = .putt
                showGreen = true
            }
            Button("View scorecard") { showScorecard = true }
            Button("Finish round", role: .destructive) { showFinishConfirm = true }
            Button("Close map") { dismiss() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Finish round?", isPresented: $showFinishConfirm) {
            Button("Finish", role: .destructive) { rounds.finishRound() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your scorecard and stats will be saved to history.")
        }
    }

    // MARK: - Chrome

    private func gpsChrome(round: GolfRound, holeNumber: Int, def: GolfHole, hole: HoleScore,
                           layout: HoleLayout, pin: GeoPoint, ball: GeoPoint, onThisHole: Bool) -> some View {
        let target = measurePoint ?? hoverPoint ?? ball
        let remaining = target.yards(to: pin)
        let helping = cos((layout.headingDegrees - round.windFromDegrees) * .pi / 180)
        let playsLike = CaddieEngine.playsLike(yards: remaining, windMph: round.windMph, windHelping: helping)
        let rec = CaddieEngine.recommendClub(for: playsLike, averages: rounds.clubAverages())

        return VStack(spacing: 0) {
            topBar(hole: hole, remaining: remaining, onThisHole: onThisHole)
            if showHolePicker {
                HoleGridPicker(
                    holes: round.holeScores.map(\.holeNumber),
                    current: holeNumber,
                    onSelect: { jump(to: $0, in: round) },
                    onFinish: { showFinishConfirm = true }
                )
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            HStack(alignment: .bottom) {
                playsLikePill(yards: remaining, playsLike: playsLike, recommendation: rec)
                Spacer()
                VStack(spacing: 12) {
                    if measurePoint != nil {
                        MapCircleButton(systemImage: "arrow.uturn.backward", label: "Revert") {
                            measurePoint = nil
                        }
                    }
                    MapCircleButton(systemImage: "mic.fill", label: "Dictate") {
                        showDictation = true
                    }
                    windDial(round)
                    MapCircleButton(systemImage: "flag.fill", label: nil) {
                        greenMode = .pin
                        showGreen = true
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            bottomBar(round: round, holeNumber: holeNumber, hole: hole, remaining: remaining)
        }
        .animation(.easeInOut(duration: 0.22), value: showHolePicker)
        .animation(.easeInOut(duration: 0.18), value: measurePoint != nil)
    }

    private func topBar(hole: HoleScore, remaining: Double, onThisHole: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 16) {
                    MapHUDChip(title: "Score", value: hole.hasScore ? "\(hole.grossScore)" : "–")
                    MapHUDChip(title: "Shot", value: "\(hole.isComplete ? max(1, hole.shots.count) : hole.shots.count + 1)")
                    MapHUDChip(title: "Putt", value: "\(hole.putts)")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.78), in: Capsule())

                Spacer(minLength: 8)

                Button {
                    greenMode = .pin
                    showGreen = true
                } label: {
                    Text("Edit Pin\nLocation")
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text(measurePoint == nil ? "Drag map to measure" : "Pinned target")
                    .font(.caption.weight(.semibold))
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 10, height: 10)
                    Text("\(Int(remaining.rounded()))")
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    Text("Yds")
                        .font(.headline.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.black.opacity(0.78), in: Capsule())

            if location.coordinate != nil, !onThisHole {
                Text("GPS is off this hole — yardages use the tee / last shot")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
            }
            if let note = hole.analysisNote, !note.isEmpty {
                Text(note)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.62), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func playsLikePill(yards: Double, playsLike: Double,
                               recommendation: (club: GolfClub, swingEffort: Double)?) -> some View {
        let club = recommendation?.club.shortName ?? "—"
        return HStack(spacing: 10) {
            Text("\(Int(yards.rounded()))")
                .font(.largeTitle.weight(.bold).monospacedDigit())
            + Text("y")
                .font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 0) {
                Text("Plays Like")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(Int(playsLike.rounded()))y  \(club)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func windDial(_ round: GolfRound) -> some View {
        VStack(spacing: 4) {
            Text("Wind")
                .font(.caption2.weight(.semibold))
            Image(systemName: "arrow.down")
                .font(.body.weight(.bold))
                .rotationEffect(.degrees(round.windFromDegrees))
            Text("\(Int(round.windMph)) mph")
                .font(.caption.weight(.bold).monospacedDigit())
        }
        .foregroundStyle(.white)
        .frame(width: 58)
        .padding(.vertical, 10)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func bottomBar(round: GolfRound, holeNumber: Int, hole: HoleScore, remaining: Double) -> some View {
        let order = round.holeScores.map(\.holeNumber)
        let idx = order.firstIndex(of: holeNumber) ?? 0
        let isLast = idx == order.count - 1
        return VStack(spacing: 10) {
            HStack {
                MapCircleButton(systemImage: "line.3.horizontal") { showTools = true }
                Spacer()
                HStack(spacing: 14) {
                    Button {
                        if idx > 0 { jump(to: order[idx - 1], in: round) }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.bold))
                    }
                    .disabled(idx == 0)
                    Button { showHolePicker.toggle() } label: {
                        Text("Hole \(holeNumber)")
                            .font(.headline.monospacedDigit())
                    }
                    Button {
                        if !isLast { jump(to: order[idx + 1], in: round) }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.bold))
                    }
                    .disabled(isLast)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.72), in: Capsule())
                Spacer()
                MapCircleButton(systemImage: "plus") {
                    openNewShot(at: measurePoint)
                }
            }
            .padding(.horizontal, 12)

            HStack(spacing: 10) {
                Button {
                    showScorecard = true
                } label: {
                    Text("Edit Score")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                Button {
                    if measurePoint != nil {
                        openNewShot(at: measurePoint)
                        return
                    }
                    rounds.updateHole(holeNumber) { $0.isComplete = true }
                    if hole.firstPuttFeet == nil, remaining < 40 {
                        greenMode = .putt
                        showGreen = true
                    }
                    if !isLast {
                        jump(to: order[idx + 1], in: round)
                    } else {
                        showScorecard = true
                    }
                } label: {
                    Text(measurePoint != nil ? "Add Shot Here" : (isLast ? "Review Scorecard" : "Go to Next Hole"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .padding(.top, 6)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Actions

    private func liveBall(round: GolfRound, holeNumber: Int) -> GeoPoint {
        if let loc = location.coordinate, GeorgetownGPS.isStanding(on: holeNumber, at: loc) {
            return loc
        }
        return round.ballCoordinate(for: holeNumber)
            ?? round.layout(for: holeNumber)?.tee
            ?? GeorgetownGPS.courseCenter
    }

    private func jump(to number: Int, in round: GolfRound) {
        selectedHole = number
        rounds.setCurrentHole(number)
        measurePoint = nil
        hoverPoint = nil
        showHolePicker = false
        if let layout = round.layout(for: number) {
            cameraPosition = layout.cameraPosition(pin: round.pinCoordinate(for: number))
        }
    }

    private func openNewShot(at point: GeoPoint?) {
        editingShot = nil
        pendingMeasure = point
        showShotEditor = true
    }
}
