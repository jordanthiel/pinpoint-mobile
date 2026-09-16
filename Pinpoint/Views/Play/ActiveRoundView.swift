import MapKit
import SwiftUI

/// Live GPS hole view: satellite map, hold-to-drag target / tee, and
/// 18Birdies-style hole / wind / score chrome. Dictation is the only extra.
struct ActiveRoundView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    @State private var selectedHole: Int?
    @State private var reviewingSwing: SwingCandidate?
    @State private var showShotEditor = false
    @State private var shotMoveFailed = false
    @State private var editingShot: TrackedShot?
    @State private var pendingMeasure: GeoPoint?
    @State private var showDictation = false
    @State private var showScorecard = false
    @State private var showHoleScore = false
    @State private var advanceAfterDismiss: Int?
    @State private var showGreen = false
    @State private var greenMode: GreenView.Mode = .pin
    @State private var showFinishConfirm = false
    @State private var showTools = false
    @State private var showNFC = false
    @State private var showWind = false
    @State private var mapHeading = 0.0
    @State private var weatherFailed = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showWatch = false
    @State private var showHolePicker = false
    @State private var showBag = false
    @State private var headerCollapsed = false
    @State private var showConfirm = false
    private struct ShotFlowPresentation: Identifiable {
        let id = UUID()
        let hole: Int
        let step: PostScoreFlow.Step
    }
    @State private var shotFlow: ShotFlowPresentation?
    @State private var pendingPostScore: Int?
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
        .preference(key: PinpointImmersiveKey.self, value: true)
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
        .onChange(of: rounds.activeRound?.currentHoleNumber) { _, number in
            guard let number, number != selectedHole, let round = rounds.activeRound else { return }
            selectedHole = number
            applyCamera(round: round, holeNumber: number)
        }
        .onDisappear { location.stop() }
        .task(id: "\(rounds.activeRound?.id.uuidString ?? "none")-\(scenePhase == .active)") {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await refreshWind()
                do { try await Task.sleep(for: .seconds(600)) } catch { return }
            }
        }
        .sheet(isPresented: $showWind) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 18) {
                    if let wind = rounds.activeRound?.courseWind {
                        Text(wind.isFresh() ? "\(Int(wind.mph.rounded())) mph · \(wind.fromDegrees == nil ? wind.compass : "From " + wind.compass)" : "Wind reading is out of date")
                            .font(.title2.bold())
                        Text("\(wind.station) · \(wind.stationID)")
                        Text("Observed \(wind.observedAt.formatted(date: .omitted, time: .shortened))")
                        Text("Nearby station conditions can differ from wind on the fairway.").font(.footnote)
                    } else {
                        Text(weatherFailed ? "Local wind is unavailable. Try again shortly." : "Loading local wind…")
                    }
                    Link("National Weather Service", destination: URL(string: "https://www.weather.gov")!)
                    Button("Refresh wind") { Task { await refreshWind() } }.buttonStyle(PrimaryButtonStyle())
                    Spacer()
                }.padding(20).navigationTitle("Local wind")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showWind = false } } }
            }.presentationDetents([.medium])
        }
    }

    private func content(round: GolfRound) -> some View {
        let holeNum = selectedHole ?? round.currentHoleNumber
        let holeDef = round.hole(holeNum)
        let hole = round.score(for: holeNum)
        let layout = round.playLayout(for: holeNum)
        let pin = round.pinCoordinate(for: holeNum) ?? layout?.pin
        let ball = liveBall(round: round, holeNumber: holeNum)
        let onThisHole = location.freshCoordinate.map { layout?.distanceToCorridor($0) ?? .infinity <= 100 } ?? false

        return ZStack {
            if let layout, let pin, let holeDef, let hole {
                let wind = round.courseWind.flatMap { $0.isFresh() ? $0 : nil }
                let helping = wind?.helping(toward: (measureOrigin ?? ball).bearing(to: measurePoint)) ?? 0
                HoleMapView(
                    position: $cameraPosition,
                    layout: layout,
                    pin: pin,
                    tee: round.teeCoordinate(for: holeNum) ?? layout.tee,
                    measurementOrigin: measureOrigin ?? ball,
                    recordedHole: hole,
                    shots: hole.shots,
                    target: measurePoint,
                    showsUserLocation: true,
                    bag: rounds.clubBag,
                    windMph: wind?.mph ?? 0,
                    windHelping: helping,
                    windFromDegrees: wind?.fromDegrees,
                    onHeadingChange: { mapHeading = $0 },
                    onMoveTarget: { point in
                        measurePoint = RangefinderSnap.advancingTarget(origin: measureOrigin ?? ball, target: point, pin: pin, layout: layout)
                    },
                    onMoveTee: { geo in
                        rounds.updateHole(holeNum) {
                            $0.teeLatitude = geo.latitude
                            $0.teeLongitude = geo.longitude
                        }
                    },
                    onSelectShot: { shot in
                        editingShot = shot
                        pendingMeasure = nil
                        showShotEditor = true
                    },
                    onMoveShot: { shot, point in
                        if !rounds.moveShot(holeNum, shot: shot, to: point) { shotMoveFailed = true }
                    },
                    onOpenBag: { showBag = true },
                    candidates: (round.swingCandidates ?? []).filter { $0.hole == holeNum && $0.state == .pending },
                    onSelectCandidate: { reviewingSwing = $0 }
                )
                .id(holeNum)
                .ignoresSafeArea()
                .onChange(of: ball) { _, origin in
                    guard measureOrigin == nil else { return }
                    let next = RangefinderSnap.advancingTarget(origin: origin, target: measurePoint, pin: pin, layout: layout)
                    if next != measurePoint { measurePoint = next }
                }
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
        .alert("Shot location not saved", isPresented: $shotMoveFailed) {
            Button("OK", role: .cancel) { }
        } message: { Text(rounds.lastError ?? "Try moving the shot again.") }
        .sheet(item: $reviewingSwing) { event in SwingReviewSheet(event: event) }
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
                .preferredColorScheme(.light)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showWatch) {
            NavigationStack {
                WatchInboxView(holeNumber: holeNum)
            }
            .preferredColorScheme(.light)
        }
        .sheet(isPresented: $showBag) {
            ClubBagView()
                .preferredColorScheme(.light)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $shotFlow, onDismiss: completeScoreTransition) { flow in
            PostScoreFlow(holeNumber: flow.hole, initialStep: flow.step, onNext: {
                advanceAfterDismiss = flow.hole
                shotFlow = nil
            })
        }
        .fullScreenCover(isPresented: $showConfirm, onDismiss: completeScoreTransition) {
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
                .preferredColorScheme(.light)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showScorecard) {
            ScorecardView()
                .preferredColorScheme(.light)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showHoleScore, onDismiss: completeScoreTransition) {
            HoleScoreEntryView(
                holeNumber: holeNum,
                onFinished: { pendingPostScore = holeNum; showHoleScore = false },
                onSkip: { advanceAfterDismiss = holeNum; showHoleScore = false },
                isLastHole: round.holeScores.last?.holeNumber == holeNum,
                saveButtonTitle: "Save & Set Pin"
            )
            .id(holeNum)
            .preferredColorScheme(.light)
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
                    onConfirmPin: { _ in showGreen = false },
                    onConfirmPutt: { feet in
                        rounds.updateHole(holeNum) { $0.firstPuttFeet = feet }
                        showGreen = false
                    },
                    onSkip: { showGreen = false }
                )
                .preferredColorScheme(.light)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showNFC) { NFCShotLogView(holeNumber: holeNum) }
        .confirmationDialog("Tools", isPresented: $showTools, titleVisibility: .visible) {
            Button("Background Location Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Scan NFC club") { showNFC = true }
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
                showHoleScore = true
            }
            Button("Confirm 1st putt") {
                greenMode = .putt
                showGreen = true
            }
            Button("View scorecard") { showScorecard = true }
            Button("End round") { showFinishConfirm = true }
            Button("Close map") { dismiss() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showFinishConfirm) {
            EndRoundSheet { dismiss() }
                .preferredColorScheme(.light)
        }
    }

    private func refreshWind() async {
        guard let round = rounds.activeRound,
              let point = round.holesSnapshot.first?.layout?.tee else { weatherFailed = true; return }
        let owner = rounds.accountID
        do {
            let wind = try await CourseWeather.shared.wind(at: point)
            guard !Task.isCancelled, rounds.accountID == owner else { return }
            rounds.updateWind(wind, roundID: round.id)
            weatherFailed = false
        } catch { if !Task.isCancelled { weatherFailed = true } }
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

            TimelineView(.periodic(from: .now, by: 5)) { _ in
                let current = location.freshCoordinate
                let anchor = round.lastShotAnchor(for: holeNumber, current: current)
                let yards = current.flatMap { point in anchor.map {
                    Int(point.yards(to: GeoPoint(latitude: $0.latitude, longitude: $0.longitude)).rounded())
                } }
                Text("\(anchor?.estimated == true ? "Est. last shot" : "Last shot") · \(yards.map { "\($0) yd" } ?? "—")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.8), in: Capsule())
                    .padding(.top, 8)
            }
            if location.authorizationDenied {
                Button("Enable location in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }.font(.caption.weight(.semibold)).padding(8)
                    .background(.black.opacity(0.8), in: Capsule())
            }
            if location.freshCoordinate != nil, !onThisHole {
                Text("GPS is off this hole — yardages use the tee / last shot")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .padding(.top, 8)
            }
            if hole.hasScore || !hole.shots.isEmpty {
                Button {
                    shotFlow = ShotFlowPresentation(hole: holeNumber, step: .shots)
                } label: {
                    Label(hole.shots.isEmpty ? "No shots saved · Add shots" : "\(hole.shots.filter { !$0.isPutt }.count) shots saved · Review", systemImage: "mappin.and.ellipse")
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
                    Button { showWind = true } label: {
                        TimelineView(.periodic(from: .now, by: 60)) { _ in
                            let wind = round.courseWind.flatMap { $0.isFresh() ? $0 : nil }
                            BirdiesWindCard(mph: wind?.mph, fromDegrees: wind?.fromDegrees, mapHeading: mapHeading,
                                            status: wind?.compass ?? (round.courseWind == nil ? "Unavailable" : "Stale"))
                        }
                    }.buttonStyle(.plain).accessibilityLabel("Local wind details")
                    Button { showNFC = true } label: {
                        Label("Scan club", systemImage: "wave.3.right").font(.caption.bold()).padding(12)
                            .foregroundStyle(.white).background(.black.opacity(0.9), in: Capsule())
                    }.buttonStyle(.plain)
                    // Button { openNewShot(at: nil) } label: {
                    //     Label("Add shot", systemImage: "plus").font(.caption.bold())
                    //         .foregroundStyle(.white).padding(12)
                    //         .background(.black.opacity(0.9), in: Capsule())
                    // }.buttonStyle(.plain)
                    BirdiesZoomRail(
                        zoomAction: { applyCamera(round: round, holeNumber: holeNumber) },
                        docAction: {
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
        let order = round.holeScores.map(\.holeNumber)
        let index = order.firstIndex(of: holeNumber)
        let previous = index.flatMap { $0 > 0 ? order[$0 - 1] : nil }
        let next = round.nextHole(after: holeNumber)
        return HStack(alignment: .bottom, spacing: 10) {
            BirdiesLeftRail(
                recenterAction: {
                    measureOrigin = nil
                    if let coordinate = location.freshCoordinate {
                        cameraPosition = .camera(MapCamera(centerCoordinate: coordinate.coordinate, distance: 450, heading: round.playLayout(for: holeNumber)?.headingDegrees ?? 0, pitch: 0))
                    } else { location.start(); applyCamera(round: round, holeNumber: holeNumber) }
                },
                scorecardAction: { showScorecard = true }
            )

            BirdiesHolePill(
                par: round.hole(holeNumber)?.par ?? 4,
                holeNumber: holeNumber,
                score: round.score(for: holeNumber).flatMap { $0.hasScore ? $0.grossScore : nil },
                canGoBack: previous != nil, canGoForward: next != nil,
                back: { if let previous { jump(to: previous, in: round) } },
                forward: { if let next { jump(to: next, in: round) } }
            ) {
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
        if let loc = location.freshCoordinate, let layout = round.playLayout(for: holeNumber), layout.distanceToCorridor(loc) <= 100 {
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
        measureOrigin = nil
        let openingTarget = layout.initialShotTarget(from: layout.tee, carryYards: rounds.bagCarry(for: .driver), par: round.hole(holeNumber)?.par)
        measurePoint = RangefinderSnap.advancingTarget(origin: origin, target: openingTarget, pin: pin, layout: layout)
        cameraPosition = layout.cameraPosition(pin: pin)
    }

    private func jump(to number: Int, in round: GolfRound) {
        selectedHole = number
        rounds.setCurrentHole(number)
        showHolePicker = false
        applyCamera(round: round, holeNumber: number)
    }

    private func openNewShot(at point: GeoPoint?) {
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

    /// Advance only after the editor/confirmation has dismissed so sheets cannot race.
    private func completeScoreTransition() {
        if let number = pendingPostScore {
            pendingPostScore = nil
            shotFlow = ShotFlowPresentation(hole: number, step: .pin)
            return
        }
        guard let number = advanceAfterDismiss, let round = rounds.activeRound else { return }
        advanceAfterDismiss = nil
        if let next = round.nextHole(after: number) {
            jump(to: next, in: round)
        } else {
            showScorecard = true
        }
    }

    private func confirmNext(holeNumber: Int) {
        advanceAfterDismiss = holeNumber
        showConfirm = false
    }
}
