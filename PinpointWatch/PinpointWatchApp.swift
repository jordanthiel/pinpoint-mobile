import SwiftUI
import CoreLocation
import WatchKit
import MapKit

@main
struct PinpointWatchApp: App {
    @State private var session = WatchSession()
    var body: some Scene {
        WindowGroup { WatchRoundView().environment(session).tint(BrandPalette.coral) }
    }
}
@MainActor @Observable
final class WatchLocation: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var location: CLLocation?
    var message = "Tap to use Watch GPS"
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters }
    func start() { manager.requestWhenInUseAuthorization(); manager.startUpdatingLocation() }
    func stop() { manager.stopUpdatingLocation() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 50 else { message = "Waiting for accurate GPS"; return }
        location = fix; message = "Watch GPS"
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { message = "GPS unavailable · retry" }
    func yards(to hole: CompanionHole, tracked: CLLocation? = nil) -> Int? {
        guard let location = tracked ?? location, abs(location.timestamp.timeIntervalSinceNow) < 60,
              let latitude = hole.pinLatitude, let longitude = hole.pinLongitude else { return nil }
        let distance = location.distance(from: CLLocation(latitude: latitude, longitude: longitude)) / 0.9144
        guard distance < 1000 else { return nil }
        return Int(distance.rounded())
    }
}
struct WatchRoundView: View {
    @Environment(WatchSession.self) private var session
    @State private var selectedHole: Int?
    @State private var location = WatchLocation()
    @State private var editor: CompanionHole?
    @State private var page = 0
    var body: some View {
        NavigationStack {
            if let round = session.round, !round.holes.isEmpty {
                let hole = round.holes.first { $0.id == (selectedHole ?? round.currentHole) } ?? round.holes[0]
                TabView(selection: $page) {
                    distancePage(round: round, hole: hole).tag(0)
                    scorePage(round: round, hole: hole).tag(1)
                    shotsPage(round: round, hole: hole).tag(2)
                    holesPage(round: round, current: hole.id).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .background(.black)
                .sheet(item: $editor) { item in
                    WatchScoreEditor(hole: item, roundID: round.id) { editor = nil; advance(round: round, hole: item.id) }
                }
                .task(id: round.id) {
                    session.tracker.select(round: round.id, hole: round.currentHole)
                    await session.tracker.startForRound()
                    if !Task.isCancelled, !session.tracker.running { location.start() }
                }
                .onChange(of: session.tracker.running) { _, running in
                    if running { location.stop() } else if session.round != nil { location.start() }
                }
                .onDisappear { location.stop() }
                .onChange(of: round.currentHole) { _, value in selectedHole = nil; session.tracker.select(round: round.id, hole: value) }
                .onChange(of: round.id) { _, _ in selectedHole = nil; editor = nil }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "figure.golf").font(.largeTitle).foregroundStyle(.mint)
                    Text("Ready to play?").font(.headline)
                    Text("Start a round in Pinpoint on your iPhone.").font(.caption).multilineTextAlignment(.center)
                    Button("Sync round") { session.refresh() }
                    if let error = session.error { Text(error).font(.caption2).foregroundStyle(.orange) }
                }.padding()
            }
        }
    }
    private func holeBadge(_ hole: CompanionHole) -> some View {
        Button { page = 3 } label: {
            HStack(spacing: 4) {
                Text(String(hole.id)).font(.headline.bold())
                Image(systemName: "flag.fill").font(.caption2)
            }.padding(.horizontal, 12).padding(.vertical, 7)
                .background(.white.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12)))
        }.buttonStyle(.plain).accessibilityLabel("Hole \(hole.id), choose hole")
    }
    private func pageHeader(_ title: String, hole: CompanionHole) -> some View {
        HStack { holeBadge(hole); Spacer(); Text(title).font(.caption).foregroundStyle(.secondary) }
    }
    private func distancePage(round: CompanionRound, hole: CompanionHole) -> some View {
        ScrollView {
            VStack(spacing: 6) {
                pageHeader("Distance", hole: hole)
                Button { if !session.tracker.running { location.start() } } label: {
                    VStack(spacing: 0) {
                        Text(location.yards(to: hole, tracked: session.tracker.currentLocation).map(String.init) ?? "—")
                            .font(.system(size: 48, weight: .bold, design: .rounded)).minimumScaleFactor(0.7)
                        Text(location.yards(to: hole, tracked: session.tracker.currentLocation) == nil ? location.message : "Yards to pin")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(.plain).accessibilityLabel("Refresh distance to pin")
                TimelineView(.periodic(from: .now, by: 5)) { _ in
                    lastShotDistance(round: round, hole: hole)
                }
                Text("Par \(hole.par)  ·  Tee \(hole.yardage) yd").font(.caption)
                HStack {
                    NavigationLink { WatchPinMap(hole: hole) } label: { Image(systemName: "map.fill").frame(maxWidth: .infinity) }
                        .accessibilityLabel("View pin map")
                    Button { record(round: round, hole: hole.id) } label: { Image(systemName: "mic.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).accessibilityLabel("Record hole voice note")
                }
            }.padding(.horizontal, 4).padding(.bottom, 20)
        }
    }
    private func lastShotDistance(round: CompanionRound, hole: CompanionHole) -> some View {
        var anchor = hole.lastShotAnchor
        if let swing = session.tracker.latestCandidate, swing.roundID == round.id, swing.hole == hole.id,
           let lat = swing.latitude, let lon = swing.longitude,
           anchor == nil || swing.timestamp > anchor!.timestamp {
            anchor = CompanionShotAnchor(latitude: lat, longitude: lon, timestamp: swing.timestamp, estimated: true)
        }
        let watchFix = (session.tracker.currentLocation ?? location.location).flatMap { abs($0.timestamp.timeIntervalSinceNow) < 30 ? $0 : nil }
        let phoneFix = round.phoneLocation.flatMap { abs($0.timestamp.timeIntervalSinceNow) < 30 ? CLLocation(latitude: $0.latitude, longitude: $0.longitude) : nil }
        let yards = (watchFix ?? phoneFix).flatMap { current in anchor.map {
            Int((current.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) / 0.9144).rounded())
        } }
        return VStack(spacing: 2) {
            Text(yards.map { "\($0) yd" } ?? "—").font(.title3.bold()).monospacedDigit()
            Text(anchor?.estimated == true ? "From estimated last shot" : "From last shot")
                .font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
    private func scorePage(round: CompanionRound, hole: CompanionHole) -> some View {
        ScrollView {
            VStack(spacing: 6) {
                pageHeader("Score", hole: hole)
                HStack { Text("Par \(hole.par)"); if let handicap = hole.handicap { Text("HCP \(handicap)") } }.font(.caption)
                Text(hole.score.map(String.init) ?? "—")
                    .background { if let score = hole.score { ScoreMark(score: score, par: hole.par, size: 58) } }
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                Text(hole.putts.map { "Putts: \($0)" } ?? "Putts: —").font(.headline)
                HStack {
                    NavigationLink { WatchPinMap(hole: hole) } label: { Image(systemName: "map.fill").frame(maxWidth: .infinity) }
                        .accessibilityLabel("View pin map")
                    Button { editor = hole } label: { Image(systemName: "pencil").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).accessibilityLabel("Edit hole \(hole.id) score")
                }
            }.padding(.horizontal, 4).padding(.bottom, 20)
        }
    }
    private func shotsPage(round: CompanionRound, hole: CompanionHole) -> some View {
        ScrollView {
            VStack(spacing: 6) {
                pageHeader("Shots", hole: hole)
                if (hole.shots ?? []).isEmpty {
                    Text("No shots logged").font(.headline).padding(.top)
                    Text("Record a voice note, then review it on iPhone to add shot details.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(hole.shots ?? []) { shot in
                    NavigationLink {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Shot \(shot.number) · \(shot.club)").font(.headline)
                                if let carry = shot.carryYards { Text("Carry: \(Int(carry)) yd") }
                                if let feet = shot.remainingFeet { Text("Finished: \(Int(feet)) ft from hole") }
                                Text(shot.detail.isEmpty ? "No additional details recorded." : shot.detail).font(.caption)
                            }
                        }
                    } label: {
                        HStack {
                            Text(String(shot.number)).font(.title3.bold())
                                .frame(width: 30, height: 34)
                                .background(shot.isPutt ? Color.green : BrandPalette.coral, in: RoundedRectangle(cornerRadius: 16))
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(shot.club).font(.caption2).foregroundStyle(.secondary)
                                if let feet = shot.remainingFeet {
                                    Text("\(Int(feet)) ft left").font(.headline)
                                } else if let carry = shot.carryYards {
                                    Text("\(Int(carry)) yd").font(.headline)
                                } else { Text("Details").font(.caption) }
                            }
                            Image(systemName: "chevron.right").font(.caption)
                        }
                    }.buttonStyle(.plain).padding(10)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                }
                Button(session.tracker.running ? "Stop tracking" : "Track swings", systemImage: "applewatch") {
                    if session.tracker.running { session.tracker.stopByUser() }
                    else { Task { await session.tracker.start() } }
                }.buttonStyle(.borderedProminent).disabled(session.tracker.starting)
                Text(session.tracker.message).font(.caption2).foregroundStyle(.secondary)
                Button("Voice note", systemImage: "mic.fill") { record(round: round, hole: hole.id) }
                    .buttonStyle(.borderedProminent)
            }.padding(.bottom, 20)
        }
    }
    private func holesPage(round: CompanionRound, current: Int) -> some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(round.holes) { hole in
                    Button { selectedHole = hole.id; page = 1 } label: {
                        HStack(spacing: 10) {
                            Text(String(hole.id)).font(.title3.bold()).frame(width: 25)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Par \(hole.par)")
                                if let handicap = hole.handicap { Text("HCP \(handicap)") }
                            }.font(.caption)
                            Spacer()
                            if let score = hole.score { Text(String(score)).font(.title3.bold()).background { ScoreMark(score: score, par: hole.par, size: 30) } }
                            else { Image(systemName: "pencil") }
                            Image(systemName: "chevron.right").font(.caption2)
                        }.padding(12).frame(maxWidth: .infinity)
                            .foregroundStyle(hole.id == current ? BrandPalette.coral : Color.white)
                            .background(hole.id == current ? Color.white : Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                    .accessibilityLabel("Hole \(hole.id), par \(hole.par), \(hole.score.map { "score \($0)" } ?? "unscored")")
                }
                NavigationLink("Round tools") { toolsPage(round: round) }.font(.caption)
            }.padding(.bottom, 20)
        }
    }
    private func toolsPage(round: CompanionRound) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(round.course).font(.headline)
                Text(session.reachable ? "Connected to iPhone" : "Cached round · phone offline").font(.caption)
                Text("Updated \(round.updatedAt.formatted(date: .omitted, time: .shortened))").font(.caption2)
                Button("Sync with iPhone") { session.refresh() }
                NavigationLink("Practice focus") { ScrollView { Text(round.focus) }.navigationTitle("Improve") }
                Text("Voice notes sync to iPhone for OpenAI transcription and review.").font(.caption2).foregroundStyle(.secondary)
                if session.pendingRecordings > 0 { Text("\(session.pendingRecordings) voice notes awaiting iPhone receipt").font(.caption2) }
                if let error = session.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }.navigationTitle("Round tools")
    }

    private func advance(round: CompanionRound, hole: Int) {
        guard let index = round.holes.firstIndex(where: { $0.id == hole }), index + 1 < round.holes.count else {
            session.error = "Last hole. Review or finish your round on iPhone."; return
        }
        selectedHole = round.holes[index + 1].id
    }
    private func record(round: CompanionRound, hole: Int) {
        do {
            try FileManager.default.createDirectory(at: WatchSession.voiceDirectory, withIntermediateDirectories: true)
            let name = "\(round.id.uuidString)_\(hole)_\(UUID().uuidString).m4a"
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            guard let controller = WKExtension.shared().visibleInterfaceController else { session.error = "Recorder isn't ready. Try again."; return }
            controller.presentAudioRecorderController(withOutputURL: file, preset: .wideBandSpeech,
                options: [WKAudioRecorderControllerOptionsMaximumDurationKey: 120]) { saved, error in
                Task { @MainActor in
                    if saved {
                        do {
                            try FileManager.default.moveItem(at: file, to: WatchSession.voiceDirectory.appendingPathComponent(name))
                            session.retryVoiceTransfers()
                        } catch { session.error = "Could not store voice note: \(error.localizedDescription)" }
                    }
                    else { try? FileManager.default.removeItem(at: file) }
                    if let error { session.error = error.localizedDescription }
                }
            }
        } catch { session.error = error.localizedDescription }
    }
}
struct WatchScoreEditor: View {
    @Environment(WatchSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let hole: CompanionHole
    let roundID: UUID
    var finished: () -> Void
    @State private var score: Int
    @State private var penalties: Int
    @State private var putts: Int
    @State private var trackPutts: Bool
    init(hole: CompanionHole, roundID: UUID, finished: @escaping () -> Void) {
        self.hole = hole; self.roundID = roundID; self.finished = finished
        _score = State(initialValue: hole.score ?? 0)
        _penalties = State(initialValue: hole.penalties ?? 0)
        _putts = State(initialValue: hole.putts ?? 0)
        _trackPutts = State(initialValue: hole.putts != nil || hole.score == nil)
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Hole \(hole.id) · Par \(hole.par)").font(.headline)
                Stepper(score == 0 ? "Choose score" : "Score \(score)", value: $score, in: 0...99)
                Toggle("Track putts", isOn: $trackPutts)
                if trackPutts { Stepper("Putts \(putts)", value: $putts, in: 0...score) }
                Stepper("Penalties \(penalties)", value: $penalties, in: 0...max(0, score - (trackPutts ? putts : 0)))
                Text("Total score includes penalties.").font(.caption2)
                Button(session.saving ? "Saving…" : "Save & Next") {
                    Task { if await session.save(CompanionScoreEdit(roundID: roundID, hole: hole.id, revision: hole.revision, score: score, putts: trackPutts ? putts : nil, penalties: penalties, advance: true)) { finished() } }
                }.buttonStyle(.borderedProminent).disabled(session.saving || score == 0 || penalties + (trackPutts ? putts : 0) > score)
                Button("Cancel") { dismiss() }.disabled(session.saving)
                if let error = session.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }
        .onChange(of: score) { _, value in putts = min(putts, value); penalties = min(penalties, max(0, value - (trackPutts ? putts : 0))) }
        .onChange(of: putts) { _, _ in penalties = min(penalties, max(0, score - (trackPutts ? putts : 0))) }
        .interactiveDismissDisabled(session.saving)
    }
}

struct WatchHolePicker: View {
    @Environment(\.dismiss) private var dismiss
    var holes: [CompanionHole]
    var select: (Int) -> Void
    var body: some View {
        List(holes) { hole in
            Button("Hole \(hole.id) · \(hole.score.map(String.init) ?? "—")") { select(hole.id); dismiss() }
        }.navigationTitle("Holes")
    }
}

struct WatchPinMap: View {
    var hole: CompanionHole
    var body: some View {
        if let latitude = hole.pinLatitude, let longitude = hole.pinLongitude {
            let pin = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            Map(initialPosition: .region(MKCoordinateRegion(center: pin, span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)))) {
                Marker("Hole \(hole.id)", systemImage: "flag.fill", coordinate: pin).tint(.green)
            }
            .mapStyle(.imagery)
            .navigationTitle("Pin location")
        } else {
            Text("No pin location available for this hole.").font(.caption).padding()
        }
    }
}
