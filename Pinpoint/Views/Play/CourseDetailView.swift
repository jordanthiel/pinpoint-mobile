import MapKit
import SwiftUI

struct CourseDetailView: View {
    @Environment(RoundStore.self) private var rounds
    @State private var showAccount = false
    @State private var showEnd = false
    @State private var showStart = false
    @State private var showActive = false
    @State private var showBag = false
    @State private var showVoice = false
    @State private var previewHole = 1
    var course: GolfCourse = SampleCourses.georgetown

    var body: some View {
        NavigationStack {
            ScrollView {
                if !showActive {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("A better round\nstarts here.").font(PinpointTheme.TypeStyle.hero)
                            Text("See the shot. Play with confidence.").font(.subheadline).foregroundStyle(PinpointTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "flag.checkered").font(.title).foregroundStyle(PinpointTheme.accentText).padding(12)
                            .background(PinpointTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    }
                    courseHeader
                    NavigationLink { WatchVoiceInboxView() } label: {
                        PinpointNavigationRow(title: "Watch voice notes", subtitle: "Review notes from your round", symbol: "applewatch")
                    }
                    Button { showAccount = true } label: {
                        PinpointNavigationRow(title: "Cloud sync", subtitle: rounds.cloudStatus, symbol: "icloud")
                    }.buttonStyle(.plain)
                    if let round = rounds.activeRound {
                        PlayUI.card {
                            Label("ROUND IN PROGRESS", systemImage: "location.fill").font(.caption.bold()).foregroundStyle(PinpointTheme.accentText)
                            Text(round.courseName).font(.title3.bold())
                            HStack(spacing: 10) {
                                StatTile(title: "Current hole", value: "\(round.currentHoleNumber)")
                                StatTile(title: "Strokes", value: "\(round.totalGross)")
                                StatTile(title: "Completed", value: "\(round.completedHoles.count)")
                            }
                            Button { showActive = true } label: {
                                Label("Continue round", systemImage: "arrow.right").frame(maxWidth: .infinity)
                            }.buttonStyle(PrimaryButtonStyle())
                            Button { showVoice = true } label: {
                                Label("Catch up by voice", systemImage: "mic.fill").frame(maxWidth: .infinity)
                            }.buttonStyle(SecondaryButtonStyle())
                            Button("End round") { showEnd = true }
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    } else {
                        Button { showStart = true } label: {
                            Label("Start a round", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity)
                        }.buttonStyle(PrimaryButtonStyle())
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("Explore the course").font(.title2.bold()); Spacer(); Text("18 holes").font(.caption).foregroundStyle(PinpointTheme.secondaryText) }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(course.holes, id: \.number) { hole in
                                    Button { previewHole = hole.number } label: {
                                        Text("\(hole.number)").font(.subheadline.bold()).frame(width: 44, height: 44)
                                            .background(previewHole == hole.number ? PinpointTheme.accent : PinpointTheme.surface, in: Circle())
                                            .foregroundStyle(PinpointTheme.primaryText)
                                    }.buttonStyle(.plain).accessibilityLabel("Preview hole \(hole.number)")
                                }
                            }
                        }
                        if let hole = course.holes.first(where: { $0.number == previewHole }), let layout = hole.layout {
                            Map(initialPosition: layout.cameraPosition(pin: layout.pin)) {
                                MapPolyline(coordinates: [layout.tee.coordinate, layout.pin.coordinate]).stroke(PinpointTheme.accent, style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
                                Marker("Tee", coordinate: layout.tee.coordinate).tint(.white)
                                Marker("Green", coordinate: layout.pin.coordinate).tint(PinpointTheme.accent)
                            }.mapStyle(.imagery).mapControls { }.frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 20)).id(previewHole)
                            HStack {
                                Text("Hole \(hole.number)").font(.headline)
                                Spacer()
                                Text("Par \(hole.par) · \(hole.yardage) yd · HCP \(hole.handicap)").font(.subheadline).foregroundStyle(PinpointTheme.secondaryText)
                            }
                            Text("Blue-tee yardages. Start a round to move your target, plan clubs and enter scores.").font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                        }
                    }
                    Button { showBag = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "bag.fill").font(.title2).foregroundStyle(PinpointTheme.accentText)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Dial in your bag").font(.headline)
                                Text("Set your carries for better shot planning.").font(.subheadline).foregroundStyle(PinpointTheme.secondaryText)
                            }
                            Spacer(); Image(systemName: "chevron.right").font(.caption)
                        }.padding(18).background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }.padding(20)
                }
            }.contentMargins(.bottom, FloatingNavigation.clearance, for: .scrollContent)
            .background(PinpointTheme.background)
                .sheet(isPresented: $showAccount) { AccountView() }
                .sheet(isPresented: $showEnd) { EndRoundSheet() }
            .navigationTitle("Pinpoint").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showBag) { ClubBagView() }
                .sheet(isPresented: $showVoice) { HoleDictationView(holeNumber: rounds.activeRound?.currentHoleNumber ?? 1) }
                .sheet(isPresented: $showStart) {
                    StartRoundView(course: course, onStarted: { showActive = true })
                        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                }
                .navigationDestination(isPresented: $showActive) { ActiveRoundView() }
                .onChange(of: rounds.activeRound?.id) { _, id in
                    if id == nil { showActive = false; showVoice = false }
                }
        }
    }

    private var courseHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Map(initialPosition: .camera(MapCamera(centerCoordinate: (course.coordinate ?? course.holes.first?.layout?.tee ?? GeorgetownGPS.courseCenter).coordinate, distance: 1400, heading: 28))) { }
                .mapStyle(.imagery).mapControls { }.allowsHitTesting(false)
            LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR COURSE").font(.caption.bold()).tracking(2).foregroundStyle(.white.opacity(0.8))
                Text(course.name).font(.title2.bold()).foregroundStyle(.white)
                Text("\(course.location.components(separatedBy: " · ").first ?? course.location) · Par \(course.totalPar)").font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }.padding(20)
        }.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 24))
    }
}
