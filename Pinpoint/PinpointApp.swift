import SwiftUI

@main
struct PinpointApp: App {
    @State private var library = SwingLibraryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .preferredColorScheme(.dark)
                .tint(PinpointTheme.accent)
        }
    }
}

struct ContentView: View {
    var body: some View {
        SwingLibraryView()
    }
}

#Preview {
    ContentView()
        .environment(SwingLibraryStore())
        .preferredColorScheme(.dark)
}
