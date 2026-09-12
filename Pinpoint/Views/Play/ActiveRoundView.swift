import MapKit
import SwiftUI

/// Live GPS hole view: satellite map, fixed-center rangefinder, and
/// 18Birdies-style hole / wind / score chrome. Dictation is the only extra.
struct ActiveRoundView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    @State private var selectedHole: Int?
    @State private var showShotEditor = false
    @State private var editingShot: TrackedShot?
    @State private var pendingMeasure: GeoPoint?
    @State private var showDictation = false
    @State private var showScorecard = false
    @State private var showHoleScore = false
    @State private var advanceAfterScore = false
    @State private var scoreSheetCommitted = false
    @State private var showGreen = false
    @State private var greenMode: GreenView.Mode = .pin
    @State private var showFinishConfirm = false
    @State private var showTools = false
    @State private var showWatch = false
    @State private var showHolePicker = false
    @State private var showBag = false
    @State private var measurePoint = Self.openingCenter
    @State private var cameraPosition: MapCameraPosition =
        GeorgetownGPS.layout(for: 1)?.cameraPosition() ?? .automatic
    @State private var location = PlayerLocation()

    private static var openingCenter: GeoPoint {
        GeorgetownGPS.layout(for: 1)?.cameraCenter ?? GeorgetownGPS.courseCenter
    }

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
            guard let round = rounds.activeRound else { return }
            let hole = selectedHole ?? round.currentHoleNumber
            selectedHole = hole
            applyCamera(round: round, holeNumber: hole)
        }
        .onDisappear { location.stop() }
    }

    private func content(round: GolfRound) -> some View {
        let holeNum = selectedHole ?? round.currentHoleNumber
        let holeDef = round.hole(holeNum)
        let hole = round.score(for: holeNum)
        let layout = round.playLayout(for: holeNum)
        let pin = round.pinCoordinate(for: holeNum) ?? layout?.pin
        let tee = round.teeCoordinate(for: holeNum) ?? layout?.tee
        let ball = liveBall(round: round, holeNumber: holeNum)
        let onThisHole = location.coordinate.map { GeorgetownGPS.isStanding(on: holeNum, at: $0) } ?? false

        return ZStack {
            if let layout, let pin, let tee, let holeDef, let hole {
                let helping = cos((layout.headingDegrees - round.windFromDegrees) * .pi / 180)
                HoleMapView(
                    position: $cameraPosition,
                    layout: layout,
                    pin: pin,
                    tee: tee,
                    ball: ball,
                    shots: hole.shots,
                    target: measurePoint,
                    showsUserLocation: onThisHole,
                    bag: rounds.clubBag,
                    windMph: round.windMph,
                    windHelping: helping,
                    onMeasure: { geo in
                        if measurePoint.yards(to: geo) > 0.4 {
                            measurePoint = geo
                        }
                    },
                    onSelectShot: { shot in
                        editingShot = shot
                        pendingMeasure = nil
                        showShotEditor = true
                    },
                    onOpenBag: { showBag = true }
                )
                .ignoresSafeArea()
                .onChange(of: holeNum) { _, newHole in
                    guard let round = rounds.activeRound else { return }
                    applyCamera(round: round, holeNumber: newHole)
                }

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
        .sheet(isPresented: $showBag) {
            ClubBagView()
                .preferredColorScheme(.dark)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
        .sheet(isPresented: $showHoleScore, onDismiss: {
            if !scoreSheetCommitted {
                advanceAfterScore = false
            }
            scoreSheetCommitted = false
        }) {
            HoleScoreEntryView(holeNumber: holeNum) { mapShots in
                scoreSheetCommitted = true
                let shouldAdvance = advanceAfterScore
                advanceAfterScore = false
                showHoleScore = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    handleScoreSaved(mapShots: mapShots, holeNumber: holeNum, shouldAdvance: shouldAdvance)
                }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.medium, .large])
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
            Button("Edit pin") {
                greenMode = .pin
                showGreen = true
            }
            Button("Reset tee") {
                rounds.updateHole(holeNum) {
                    $0.teeLatitude = nil
                    $0.teeLongitude = nil
                }
            }
            if rounds.watchDetector.unclaimedCount > 0 {
                Button("Watch shots (\(rounds.watchDetector.unclaimedCount))") { showWatch = true }
            }
            Button("My bag") { showBag = true }
            Button("Dictate this hole") { showDictation = true }
            Button(hole?.hasScore == true ? "Edit this hole's score" : "Enter this hole's score") {
                advanceAfterScore = false
                showHoleScore = true
            }
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
        VStack(spacing: 0) {
            topBar(round: round, holeNumber: holeNumber, def: def, ball: ball, pin: pin, layout: layout)

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

            if location.coordinate != nil, !onThisHole {
                Text("GPS is off this hole — yardages use the tee / last shot")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .padding(.top, 8)
            }
            if hole.hasScore, hole.shots.isEmpty {
                Button {
                    openNewShot(at: measurePoint)
                } label: {
                    Label("Score saved — map your shots", systemImage: "mappin.and.ellipse")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(PinpointTheme.accent.opacity(0.85), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            if let note = hole.analysisNote, !note.isEmpty {
                Text(note)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.62), in: Capsule())
                    .padding(.top, 8)
            }

            Spacer(minLength: 0)
                .allowsHitTesting(false)

            HStack(alignment: .bottom) {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                VStack(spacing: 10) {
                    BirdiesWindCard(mph: round.windMph, fromDegrees: round.windFromDegrees)
                    BirdiesRailButton(systemImage: "plus", accessibilityTitle: "Add shot") {
                        openNewShot(at: measurePoint)
                    }
                    BirdiesRailButton(systemImage: "dot.scope", accessibilityTitle: "Recenter hole") {
                        applyCamera(round: round, holeNumber: holeNumber)
                    }
                    BirdiesRailButton(systemImage: "doc", accessibilityTitle: "Hole score") {
                        advanceAfterScore = false
                        showHoleScore = true
                    }
                    BirdiesRailButton(systemImage: "mic.fill", accessibilityTitle: "Dictate hole") {
                        showDictation = true
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            bottomBar(round: round, holeNumber: holeNumber)
        }
        .animation(.easeInOut(duration: 0.22), value: showHolePicker)
    }

    private func topBar(round: GolfRound, holeNumber: Int, def: GolfHole,
                        ball: GeoPoint, pin: GeoPoint, layout: HoleLayout) -> some View {
        let mid = Int(ball.yards(to: layout.greenCenter).rounded())
        let toGreen = Int(ball.yards(to: pin).rounded())
        let order = round.holeScores.map(\.holeNumber)
        let idx = order.firstIndex(of: holeNumber) ?? 0
        let isLast = idx == order.count - 1

        return HStack(spacing: 6) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Button { showHolePicker.toggle() } label: {
                VStack(spacing: 1) {
                    Text("\(holeNumber)")
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(width: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hole \(holeNumber)")

            HStack(spacing: 0) {
                BirdiesTopStat(title: "Mid", value: "\(mid)y")
                BirdiesTopStat(title: "Green", value: "\(toGreen)y")
                BirdiesTopStat(title: "Par", value: "\(def.par)")
                BirdiesTopStat(title: round.teeName, value: "\(def.yardage)")
                BirdiesTopStat(title: "Handicap", value: "\(def.handicap)")
            }
            .frame(maxWidth: .infinity)

            Button {
                if !isLast {
                    jump(to: order[idx + 1], in: round)
                } else {
                    showScorecard = true
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLast ? "Review scorecard" : "Next hole")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black, in: Capsule())
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    private func bottomBar(round: GolfRound, holeNumber: Int) -> some View {
        let order = round.holeScores.map(\.holeNumber)
        let idx = order.firstIndex(of: holeNumber) ?? 0
        let isLast = idx == order.count - 1

        return HStack(alignment: .bottom, spacing: 8) {
            BirdiesDockButton(systemImage: "target", title: "Scorecard") {
                showScorecard = true
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 14) {
                Button {
                    if idx > 0 { jump(to: order[idx - 1], in: round) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.bold))
                }
                .disabled(idx == 0)
                .opacity(idx == 0 ? 0.35 : 1)

                Button { showHolePicker.toggle() } label: {
                    Text("Hole \(holeNumber)")
                        .font(.headline.monospacedDigit())
                }

                Button {
                    if !isLast {
                        jump(to: order[idx + 1], in: round)
                    } else {
                        showScorecard = true
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.black, in: Capsule())

            BirdiesDockButton(systemImage: "doc.badge.gearshape", title: "Tools") {
                showTools = true
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func liveBall(round: GolfRound, holeNumber: Int) -> GeoPoint {
        if let loc = location.coordinate, GeorgetownGPS.isStanding(on: holeNumber, at: loc) {
            return loc
        }
        return round.ballCoordinate(for: holeNumber)
            ?? round.teeCoordinate(for: holeNumber)
            ?? round.layout(for: holeNumber)?.tee
            ?? GeorgetownGPS.courseCenter
    }

    private func applyCamera(round: GolfRound, holeNumber: Int) {
        if let layout = round.playLayout(for: holeNumber) {
            cameraPosition = layout.cameraPosition(pin: round.pinCoordinate(for: holeNumber))
            measurePoint = layout.cameraCenter
        }
    }

    private func jump(to number: Int, in round: GolfRound) {
        selectedHole = number
        rounds.setCurrentHole(number)
        showHolePicker = false
        applyCamera(round: round, holeNumber: number)
    }

    private func openNewShot(at point: GeoPoint) {
        editingShot = nil
        pendingMeasure = point
        showShotEditor = true
    }

    private func handleScoreSaved(mapShots: Bool, holeNumber: Int, shouldAdvance: Bool) {
        if mapShots {
            openNewShot(at: measurePoint)
            return
        }
        guard shouldAdvance, let round = rounds.activeRound,
              let hole = round.score(for: holeNumber)
        else { return }
        let pin = round.pinCoordinate(for: holeNumber)
        let ball = liveBall(round: round, holeNumber: holeNumber)
        let toPin = pin.map { ball.yards(to: $0) } ?? 999
        advanceHole(round: round, holeNumber: holeNumber, hole: hole, toPin: toPin)
    }

    private func advanceHole(round: GolfRound, holeNumber: Int, hole: HoleScore, toPin: Double) {
        rounds.updateHole(holeNumber) { $0.isComplete = true }
        if hole.firstPuttFeet == nil, toPin < 40 {
            greenMode = .putt
            showGreen = true
        }
        let order = round.holeScores.map(\.holeNumber)
        let idx = order.firstIndex(of: holeNumber) ?? 0
        if idx < order.count - 1 {
            jump(to: order[idx + 1], in: round)
        } else {
            showScorecard = true
        }
    }
}
