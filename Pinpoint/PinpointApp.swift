import SwiftUI

@main
struct PinpointApp: App {
    @State private var library = SwingLibraryStore()
    @State private var rounds = RoundStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(rounds)
                .preferredColorScheme(.dark)
                .tint(PinpointTheme.accent)
        }
    }
}

struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    ContentView()
        .environment(SwingLibraryStore())
        .environment(RoundStore())
        .preferredColorScheme(.dark)
}
