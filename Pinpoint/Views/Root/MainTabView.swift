import SwiftUI

struct MainTabView: View {
    @Environment(RoundStore.self) private var rounds
    @State private var selection = 0
    @State private var catalog = CourseCatalog()
    @State private var immersive = false
    @State private var activityRoundPresented = false
    private let tabs = [("Play", "figure.golf"), ("Courses", "map"), ("Swings", "video"), ("Me", "person.crop.circle")]

    var body: some View {
        TabView(selection: $selection) {
            Group { if selection == 0 { CourseDetailView(course: catalog.selectedCourse ?? SampleCourses.georgetown) } }
                .toolbar(.hidden, for: .tabBar).tag(0)
            Group { if selection == 1 { CoursesView(catalog: catalog, onPlay: { selection = 0 }) } }
                .toolbar(.hidden, for: .tabBar).tag(1)
            Group { if selection == 2 { SwingLibraryView() } }.toolbar(.hidden, for: .tabBar).tag(2)
            Group { if selection == 3 { MeView() } }.toolbar(.hidden, for: .tabBar).tag(3)
        }
        .toolbar(.hidden, for: .tabBar)
        .task { await catalog.refresh() }
        .onOpenURL { url in
            guard url.scheme == "pinpoint", url.host == "round",
                  let id = UUID(uuidString: url.lastPathComponent), rounds.activeRound?.id == id else { return }
            selection = 0
            activityRoundPresented = true
        }
        .fullScreenCover(isPresented: $activityRoundPresented) {
            NavigationStack { ActiveRoundView() }
        }
        .onPreferenceChange(PinpointImmersiveKey.self) { immersive = $0 }
        .overlay(alignment: .bottom) { navigationBar }
        .overlay(alignment: .top) {
            if let message = rounds.lastError {
                Text(message).font(.footnote).foregroundStyle(.white).padding(14)
                    .background(PinpointTheme.primaryText, in: RoundedRectangle(cornerRadius: 16))
                    .padding().onTapGesture { rounds.lastError = nil }
            }
        }
    }
    @ViewBuilder private var navigationBar: some View {
            if !immersive {
                HStack(spacing: 2) {
                    ForEach(tabs.indices, id: \.self) { index in
                        Button { selection = index } label: {
                            VStack(spacing: 3) {
                                Image(systemName: tabs[index].1)
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(width: 24, height: 22)
                                    .foregroundStyle(selection == index ? PinpointTheme.accent : .white.opacity(0.8))
                                Text(tabs[index].0).font(.caption2.weight(.medium)).foregroundStyle(.white)
                            }.frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.plain)
                            .accessibilityLabel(tabs[index].0)
                            .accessibilityAddTraits(selection == index ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(PinpointTheme.primaryText, in: Capsule())
                .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
                .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 0)
            }
        }

}
