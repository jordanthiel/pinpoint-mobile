import SwiftUI

/// Shared ending choices for the live map, home card, and recap.
struct EndRoundSheet: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss
    var recap: String? = nil
    var onEnded: () -> Void = {}
    @State private var confirmDelete = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let round = rounds.activeRound {
                        PinpointPageHeading(title: "Done for today?", subtitle: "\(round.holeScores.filter(\.hasScore).count) of \(round.holeScores.count) holes scored. Your recorded shots and notes stay with a saved round.")
                        if round.nineHoleNumbers != nil {
                            Button("Save as 9-hole round") { save(nine: true) }
                                .buttonStyle(PrimaryButtonStyle())
                        }
                        Button(round.holeScores.allSatisfy(\.hasScore) ? "Save completed round" : "Save unfinished round") { save(nine: false) }
                            .buttonStyle(SecondaryButtonStyle())
                        Button("Keep playing") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                        Button("Delete round", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }.padding(20)
            }.background(PinpointTheme.background)
                .navigationTitle("End round").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .alert("Delete this round?", isPresented: $confirmDelete) {
                    Button("Delete round", role: .destructive) {
                        if rounds.discardActiveRound() { dismiss(); onEnded() } else { failed = true }
                    }
                    Button("Keep round", role: .cancel) { }
                } message: { Text("This removes the active round and its scores, shots, and notes. It will not be saved to history.") }
                .alert("Round not changed", isPresented: $failed) { Button("OK", role: .cancel) { } }
                    message: { Text(rounds.lastError ?? "Please try again.") }
        }
    }

    private func save(nine: Bool) {
        if rounds.finishRound(saveAsNine: nine, recap: recap) { dismiss(); onEnded() }
        else { failed = true }
    }
}
