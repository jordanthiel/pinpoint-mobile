import SwiftUI
import MapKit

struct CoursesView: View {
    @Bindable var catalog: CourseCatalog
    var onPlay: () -> Void
    @State private var location = PlayerLocation()
    @State private var search = ""
    @State private var nearby = false
    @State private var origin: GeoPoint?
    @State private var selected: CatalogCourse?
    @State private var mapsError = false
    @State private var locating = false
    private var results: [CatalogCourse] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalog.courses.filter { course in
            (query.isEmpty || "\(course.name) \(course.locality) \(course.address)".localizedCaseInsensitiveContains(query)) &&
            (!nearby || origin.map { $0.yards(to: course.point) <= 50 * 1760 } == true)
        }.sorted { a, b in
            if let origin { return origin.yards(to: a.point) < origin.yards(to: b.point) }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PinpointPageHeading(title: "Find your next round.", subtitle: "Explore courses in the Pinpoint directory.")
                    TextField("Search course, city or address", text: $search)
                        .textFieldStyle(.plain).padding(14).background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Search courses")
                    HStack {
                        Button("All courses") { nearby = false }.foregroundStyle(!nearby ? PinpointTheme.accentText : PinpointTheme.secondaryText)
                        Spacer()
                        Button("Near me · 50 mi") {
                            if origin != nil { nearby = true }
                            else { locating = true; location.start() }
                        }.foregroundStyle(nearby ? PinpointTheme.accentText : PinpointTheme.secondaryText)
                    }.font(.subheadline.weight(.semibold))
                    if locating && !location.authorizationDenied { Text("Finding your location…").font(.caption) }
                    if location.authorizationDenied {
                        Button("Enable location in Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                        Text("You can still search by course name or city.").font(.caption)
                    }
                    if let message = catalog.message {
                        Text(message).font(.footnote).foregroundStyle(PinpointTheme.secondaryText)
                        Button("Retry") { Task { await catalog.refresh() } }
                    }
                    if catalog.loading { ProgressView("Loading courses…") }
                    if !results.isEmpty {
                        courseMap
                        Text("\(results.count) published \(results.count == 1 ? "course" : "courses")\(nearby ? " within 50 miles" : "")")
                            .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                    } else if !catalog.loading {
                        ContentUnavailableView("No courses found", systemImage: "flag", description: Text("Try another city or show all courses. New locations will appear here as they’re added to the directory."))
                    }
                    ForEach(results) { course in
                        Button { selected = course } label: {
                            PinpointNavigationRow(title: course.name, subtitle: subtitle(course), symbol: "flag")
                        }.buttonStyle(.plain)
                    }
                }.padding(20).padding(.bottom, FloatingNavigation.clearance)
            }.background(PinpointTheme.background).navigationTitle("Courses").navigationBarTitleDisplayMode(.inline)
                .refreshable { await catalog.refresh() }
                .task { await catalog.refresh() }
                .onChange(of: location.coordinate) { _, point in
                    guard let point = location.freshCoordinate else { return }
                    origin = point; nearby = true; locating = false; location.stop()
                }
                .onDisappear { location.stop() }
                .sheet(item: $selected) { course in
                    courseDetails(course)
                }
        }
    }
    private var catalogMapPosition: MapCameraPosition {
        guard results.count == 1, let course = results.first else { return .automatic }
        return .region(MKCoordinateRegion(center: course.point.coordinate,
                                         span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)))
    }
    private var courseMap: some View {
                        Map(initialPosition: catalogMapPosition) {
                            ForEach(Array(results.prefix(50))) { course in
                                MapKit.Annotation(course.name, coordinate: course.point.coordinate) {
                                    Button { selected = course } label: {
                                        Image(systemName: "flag.fill").padding(9).foregroundStyle(.white)
                                            .background(PinpointTheme.primaryText, in: Circle())
                                    }.accessibilityLabel(course.name)
                                }
                            }
                        }.id(results.map(\.id)).frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 20))
    }
    private func courseDetails(_ course: CatalogCourse) -> some View {
                    NavigationStack {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(course.name).font(.title2.bold())
                            Text(course.address).foregroundStyle(PinpointTheme.secondaryText)
                            Text(course.locality).font(.subheadline)
                            Button {
                                let item = MKMapItem(placemark: MKPlacemark(coordinate: course.point.coordinate))
                                item.name = course.name
                                if !item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]) { mapsError = true }
                            } label: { Label("Directions in Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond") }
                                .buttonStyle(PrimaryButtonStyle())
                            if course.definition != nil {
                                Button("Play this course") {
                                    catalog.selectedID = course.id; selected = nil; onPlay()
                                }.buttonStyle(SecondaryButtonStyle())
                            } else {
                                Text("Shot maps and scoring are not available for this course yet.").font(.footnote)
                            }
                            Spacer()
                        }.padding(20).navigationTitle("Course details").navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selected = nil } } }
                            .alert("Could not open Apple Maps", isPresented: $mapsError) { Button("OK", role: .cancel) {} }
                    }.presentationDetents([.medium, .large])
    }
    private func subtitle(_ course: CatalogCourse) -> String {
        let miles = origin.map { String(format: " · %.1f mi", $0.yards(to: course.point) / 1760) } ?? ""
        return course.locality + miles + (course.definition != nil ? " · Ready to play" : "")
    }
}
