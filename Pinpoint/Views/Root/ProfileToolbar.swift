import SwiftUI

/// Account/profile button for the navigation bar. Presents the shared
/// AccountView sheet (sign in, cloud sync status, sign out).
struct ProfileBarButton: View {
    @Environment(SwingLibraryStore.self) private var library
    @State private var showAccount = false

    var body: some View {
        Button {
            showAccount = true
        } label: {
            Image(systemName: library.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
        }
        .accessibilityLabel("Profile")
        .sheet(isPresented: $showAccount) {
            AccountView()
                .preferredColorScheme(.light)
                .presentationDragIndicator(.visible)
        }
    }
}

extension View {
    /// Adds the profile button to the navigation bar's trailing side.
    /// Attach to a NavigationStack to keep it visible on pushed screens too.
    func profileToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ProfileBarButton()
            }
        }
    }
}
