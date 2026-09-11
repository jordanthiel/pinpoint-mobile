import MapKit
import SwiftUI

/// Course home: header art, Start Round, tips + personal stats at this course.
struct CourseDetailView: View {
    @Environment(RoundStore.self) private var rounds
    @State private var showStart = false
    @State private var showActive = false

    private var course: GolfCourse { SampleCourses.georgetown }

    var body: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        courseHeader
                        if rounds.activeRound != nil {
                            resumeCard
                        }
                        Button {
                            showStart = true
                        } label: {
                            Label("Start Round", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        infoCard(title: "Course Tips", subtitle: "Local tips for this course.", icon: "lightbulb")
                        myCourseStats
                        watchCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Courses")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showStart) {
                StartRoundView(course: course, onStarted: { showActive = true })
                    .preferredColorScheme(.dark)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .navigationDestination(isPresented: $showActive) {
                if rounds.activeRound != nil {
                    ActiveRoundView()
                }
            }
        }
    }

    private var courseHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Map(initialPosition: .camera(MapCamera(
                centerCoordinate: (course.coordinate ?? GeorgetownGPS.courseCenter).coordinate,
                distance: 1400,
                heading: 28,
                pitch: 0
            )), scope: nil) {
                if let tee = course.layout(for: 1)?.tee, let pin = course.layout(for: 1)?.pin {
                    MapPolyline(coordinates: [tee.coordinate, pin.coordinate])
                        .stroke(.white.opacity(0.7), lineWidth: 2)
                }
            }
            .mapStyle(.imagery)
            .mapControls { }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .allowsHitTesting(false)

            LinearGradient(colors: [.clear, .black.opacity(0.72)],
                           startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.white)
                    Text(course.location)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Text(course.name)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text("Par \(course.totalPar) · Blue 5374 yds")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
        }
    }

    private var resumeCard: some View {
        Group {
            if let round = rounds.activeRound {
                NavigationLink {
                    ActiveRoundView()
                } label: {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundStyle(PinpointTheme.accent)
                        VStack(alignment: .leading) {
                            Text("Round in progress — Hole \(round.currentHoleNumber)")
                                .font(.headline)
                            if round.completedHoles.isEmpty {
                                Text("\(round.totalGross) strokes")
                                    .font(.subheadline)
                                    .foregroundStyle(PinpointTheme.secondaryText)
                            } else {
                                Text("\(round.totalGross) strokes · \(round.completedToParLabel)")
                                    .font(.subheadline)
                                    .foregroundStyle(PinpointTheme.secondaryText)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(PinpointTheme.secondaryText)
                    }
                    .padding(16)
                    .background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func infoCard(title: String, subtitle: String, icon: String) -> some View {
        NavigationLink {
            Text(subtitle)
                .navigationTitle(title)
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(PinpointTheme.accent)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(PinpointTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(PinpointTheme.secondaryText)
            }
            .padding(16)
            .background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var myCourseStats: some View {
        let stats = rounds.allRoundsStats
        return PlayUI.card {
            Text("My Course Stats")
                .font(.headline)
            if stats.holesPlayed == 0 {
                Text("No tracked holes yet. Start a round to build your averages.")
                    .font(.subheadline)
                    .foregroundStyle(PinpointTheme.secondaryText)
            } else {
                HStack(spacing: 10) {
                    StatTile(title: "Avg / hole", value: String(format: "%.1f", stats.averageScore ?? 0))
                    StatTile(title: "Fairways", value: stats.fairwayPct.map { "\(Int($0))%" } ?? "–")
                    StatTile(title: "GIR", value: stats.girPct.map { "\(Int($0))%" } ?? "–")
                }
            }
        }
    }

    private var watchCard: some View {
        NavigationLink {
            WatchInboxView()
        } label: {
            HStack {
                Image(systemName: "applewatch")
                    .font(.title3)
                    .foregroundStyle(PinpointTheme.accent)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch shot tracking")
                        .font(.headline)
                    Text(watchSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(PinpointTheme.secondaryText)
                }
                Spacer()
                if rounds.watchDetector.unclaimedCount > 0 {
                    Text("\(rounds.watchDetector.unclaimedCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.red, in: Circle())
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(PinpointTheme.secondaryText)
                }
            }
            .padding(16)
            .background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var watchSubtitle: String {
        let pending = rounds.watchDetector.unclaimedCount
        if rounds.watchDetector.isListening { return "Listening… \(pending) unclaimed" }
        return pending > 0 ? "\(pending) swings waiting for review" : "Motion + sound auto-detect"
    }
}
