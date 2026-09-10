import SwiftUI

/// Root tabs: Play (on-course), Swings (video library), Me (review stats).
struct MainTabView: View {
    @Environment(RoundStore.self) private var rounds

    var body: some View {
        TabView {
            CourseDetailView()
                .tabItem {
                    Label("Play", systemImage: "figure.golf")
                }
            SwingLibraryView()
                .tabItem {
                    Label("Swings", systemImage: "video")
                }
            PlayStatsView()
                .tabItem {
                    Label("Me", systemImage: "person.crop.circle")
                }
        }
        .overlay(alignment: .bottom) {
            if let message = rounds.lastError {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding()
                    .onTapGesture { rounds.lastError = nil }
            }
        }
    }
}
