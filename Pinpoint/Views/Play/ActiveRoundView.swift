import MapKit
import SwiftUI

/// Live GPS hole view: satellite map, hold-to-drag target / tee, and
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
    @State private var headerCollapsed = false
    @State private var showConfirm = false
    @State private var measurePoint = Self.openingCenter
    @State private var measureOrigin: GeoPoint?
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
            // Screenshot-harness hooks (inert without the launch flags).
            if CommandLine.arguments.contains("--ui-hole-collapsed") {
                headerCollapsed = true
            }
            guard let round = rounds.activeRound else { return }
            let hole = selectedHole ?? round.currentHoleNumber
            selectedHole = hole
            applyCamera(round: round, holeNumber: hole)
            if CommandLine.arguments.contains("--ui-hole-sheet") {
                showHoleScore = true
            }
            for arg in CommandLine.arguments where arg.hasPrefix("--ui-hole-green=") {
                greenMode = arg.hasSuffix("putt") ? .putt : .pin
                showGreen = true
            }
            if CommandLine.arguments.contains("--ui-hole-confirm") {
                seedConfirmHarness(holeNumber: hole)
                showConfirm = true
            }
        }
        .onDisappear { location.stop() }
    }

    private func content(round: GolfRound) -> some View {
        let holeNum = selectedHole ?? round.currentHoleNumber
        let holeDef = round.hole(holeNum)
        let hole = round.score(for: holeNum)
        let layout = round.playLayout(for: holeNum)
        let pin = round.pinCoordinate(for: holeNum) ?? layout?.pin
        let ball = liveBall(round: round, holeNumber: holeNum)
        let onThisHole = location.coordinate.map { GeorgetownGPS.isStanding(on: holeNum, at: $0) } ?? false

        return ZStack {
            if let layout, let pin, let holeDef, let hole {
                let helping = cos((layout.headingDegrees - round.windFromDegrees) * .pi / 180)
                HoleMapView(
                    position: $cameraPosition,
                    layout: layout,
                    pin: pin,
                    tee: measureOrigin ?? ball,
                    shots: hole.shots,
                    target: measurePoint,
                    showsUserLocation: onThisHole,
                    bag: rounds.clubBag,
                    windMph: round.windMph,
                    windHelping: helping,
                    onMoveTarget: { measurePoint = $0 },
                    onMoveTee: { geo in
                        measureOrigin = geo
                        if !hole.shots.contains(where: { $0.end != nil }) {
                            rounds.updateHole(holeNum) {
                                $0.teeLatitude = geo.latitude
                                $0.teeLongitude = geo.longitude
                            }
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
                          layout: layout, pin: pin, from: measureOrigin ?? ball, onThisHole: onThisHole)
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
        .fullScreenCover(isPresented: $showConfirm) {
            if let layout {
                let pinGeo = round.pinCoordinate(for: holeNum) ?? layout.pin
                let teeGeo = layout.tee
                HoleConfirmView(
                    holeNumber: holeNum,
                    layout: layout,
                    pin: pinGeo,
                    tee: teeGeo,
                    onEditPin: {
                        showConfirm = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            greenMode = .pin
                            showGreen = true
                        }
                    },
                    onEditScore: {
                        showConfirm = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showHoleScore = true
                        }
                    },
                    onNext: { confirmNext(holeNumber: holeNum) },
                    onMenu: {
                        showConfirm = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showTools = true
                        }
                    }
                )
            }
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
            HoleScoreEntryView(holeNumber: holeNum) {
                scoreSheetCommitted = true
                advanceAfterScore = false
                showHoleScore = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    greenMode = .pin
                    showGreen = true
                }
            }
            .preferredColorScheme(.light)
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
                    onConfirmPin: { _ in
                        showGreen = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            greenMode = .putt
                            showGreen = true
                        }
                    },
                    onConfirmPutt: { feet in
                        rounds.updateHole(holeNum) { $0.firstPuttFeet = feet }
                        showGreen = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showConfirm = true
                        }
                    },
                    onSkip: {
                        let wasPutt = greenMode == .putt
                        showGreen = false
                        if wasPutt {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                showConfirm = true
                            }
                        }
                    }
                )
                .preferredColorScheme(.light)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog("Tools", isPresented: $showTools, titleVisibility: .visible) {
            Button("Add shot") { openNewShot(at: measurePoint) }
            Button("Recenter hole") {
                applyCamera(round: round, holeNumber: holeNum)
            }
            Button("Edit pin") {
                greenMode = .pin
                showGreen = true
            }
            Button("Reset tee") {
                measureOrigin = nil
                rounds.updateHole(holeNum) {
                    $0.teeLatitude = nil
                    $0.teeLongitude = nil
                }
                if let layout = rounds.activeRound?.playLayout(for: holeNum) {
                    measureOrigin = layout.tee
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
                           layout: HoleLayout, pin: GeoPoint, from: GeoPoint, onThisHole: Bool) -> some View {
        VStack(spacing: 0) {
            topBar(round: round, holeNumber: holeNumber, def: def, from: from, pin: pin, layout: layout)

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

            bottomBar(holeNumber: holeNumber, round: round)
        }
        .overlay(alignment: .trailing) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    BirdiesWindCard(mph: round.windMph, fromDegrees: round.windFromDegrees)
                    BirdiesZoomRail(
                        zoomAction: { applyCamera(round: round, holeNumber: holeNumber) },
                        docAction: {
                            advanceAfterScore = false
                            showHoleScore = true
                        },
                        toolsAction: { showTools = true }
                    )
                }
            }
            .padding(.trailing, 10)
            .offset(y: 125)
        }
        .animation(.easeInOut(duration: 0.22), value: showHolePicker)
    }

    private func topBar(round: GolfRound, holeNumber: Int, def: GolfHole,
                        from: GeoPoint, pin: GeoPoint, layout: HoleLayout) -> some View {
        let mid = Int(from.yards(to: layout.greenCenter).rounded())

        return HStack(alignment: .top, spacing: 10) {
            BirdiesCircleNavButton(systemImage: "chevron.left", accessibilityTitle: "Back") {
                dismiss()
            }

            HStack(spacing: 0) {
                Button { showHolePicker.toggle() } label: {
                    VStack(spacing: 1) {
                        Text("\(holeNumber)")
                            .font(.system(size: 33, weight: .bold, design: .rounded).monospacedDigit())
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 54)
                    .padding(.vertical, 5)
                    .background(
                        Color.black,
                        in: UnevenRoundedRectangle(
                            cornerRadii: RectangleCornerRadii(
                                topLeading: 24, bottomLeading: 24,
                                bottomTrailing: 0, topTrailing: 0
                            ),
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hole \(holeNumber)")

                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 1, height: 44)

                HStack(spacing: 2) {
                    BirdiesTopStat(title: "Mid Green", value: "\(mid)", unit: "Yds")
                    if !headerCollapsed {
                        BirdiesTopStat(title: "Par", value: "\(def.par)")
                        BirdiesTopStat(title: round.teeName, value: "\(def.yardage)")
                        BirdiesTopStat(title: "Handicap", value: "\(def.handicap)")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.trailing, 4)
            }
            .padding(.leading, 0)
            .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .trailing) {
                Button {
                    headerCollapsed.toggle()
                } label: {
                    BirdiesBlueBadge(systemImage: headerCollapsed ? "chevron.left" : "chevron.right", size: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(headerCollapsed ? "Expand hole details" : "Collapse to hole and distance"))
                .offset(x: 8, y: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .animation(.easeInOut(duration: 0.22), value: headerCollapsed)
    }

    private func bottomBar(holeNumber: Int, round: GolfRound) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            BirdiesLeftRail(
                recenterAction: { applyCamera(round: round, holeNumber: holeNumber) },
                scorecardAction: { showScorecard = true }
            )

            BirdiesHolePill(holeNumber: holeNumber) {
                advanceAfterScore = false
                showHoleScore = true
            }
            .frame(maxWidth: 220)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)

            Button {
                showDictation = true
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dictate this hole"))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
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
        guard let layout = round.playLayout(for: holeNumber) else { return }
        let pin = round.pinCoordinate(for: holeNumber) ?? layout.pin
        let origin = liveBall(round: round, holeNumber: holeNumber)
        measureOrigin = origin
        // The target moves only by direct drag now (never by camera motion),
        // so seed it at the framed corridor midpoint — the settled value the
        // camera-center tracking used to converge on.
        measurePoint = layout.cameraCenter
        cameraPosition = layout.cameraPosition(pin: pin)
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

    /// Screenshot-harness seeding for the confirm screen: a 4 with two
    /// mapped shots (driver + 9-iron), two putts, and a 19-foot first putt.
    private func seedConfirmHarness(holeNumber: Int) {
        guard let round = rounds.activeRound,
              let layout = round.playLayout(for: holeNumber)
        else { return }
        let pin = round.pinCoordinate(for: holeNumber) ?? layout.pin
        let mid = layout.tee.interpolated(to: pin, t: 0.5)
        let nearGreen = pin.interpolated(to: layout.tee, t: 0.06)
        rounds.addShot(holeNumber, TrackedShot(
            number: 1,
            club: .driver, lie: .tee,
            distanceToPinBeforeYards: layout.tee.yards(to: pin),
            carryYards: layout.tee.yards(to: mid),
            start: layout.tee, end: mid, source: .manual
        ))
        rounds.addShot(holeNumber, TrackedShot(
            number: 2,
            club: .iron9, lie: .rough,
            distanceToPinBeforeYards: mid.yards(to: pin),
            carryYards: mid.yards(to: nearGreen),
            start: mid, end: nearGreen, source: .manual
        ))
        rounds.updateHole(holeNumber) {
            $0.recordedScore = 4
            $0.recordedPutts = 2
            $0.firstPuttFeet = 19
            $0.isComplete = true
        }
    }

    /// "Go to Next Hole" from the shot-details confirm screen.
    private func confirmNext(holeNumber: Int) {
        guard let round = rounds.activeRound else { return }
        rounds.updateHole(holeNumber) { $0.isComplete = true }
        showConfirm = false
        let order = round.holeScores.map(\.holeNumber)
        let idx = order.firstIndex(of: holeNumber) ?? 0
        if idx < order.count - 1 {
            jump(to: order[idx + 1], in: round)
        } else {
            showScorecard = true
        }
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
