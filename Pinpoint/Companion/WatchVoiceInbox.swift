import SwiftUI

struct WatchVoiceNote: Identifiable {
    var url: URL
    var roundID: UUID
    var hole: Int
    var id: String { url.lastPathComponent }
}
@MainActor @Observable
final class WatchVoiceInbox {
    static let shared = WatchVoiceInbox()
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pinpoint/WatchVoice", isDirectory: true)
    }
    var notes: [WatchVoiceNote] = []
    init() { reload() }
    func reload() {
        notes = ((try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []).compactMap { url in
            let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_")
            guard parts.count == 3, let round = UUID(uuidString: String(parts[0])), let hole = Int(parts[1]) else { return nil }
            return WatchVoiceNote(url: url, roundID: round, hole: hole)
        }.sorted { $0.id < $1.id }
    }
}
struct WatchVoiceInboxView: View {
    @Environment(RoundStore.self) private var rounds
    @State private var inbox = WatchVoiceInbox.shared
    @State private var busy: String?
    @State private var error: String?
    @State private var review: WatchTranscript?
    @State private var removing: WatchVoiceNote?
    private struct WatchTranscript: Identifiable { let id = UUID(); var hole: Int; var text: String }
    var body: some View {
        List {
            Text("Watch recordings stay here until you remove them. Transcribe with OpenAI, then review the scores before saving.")
                .font(.caption).foregroundStyle(.secondary)
            if inbox.notes.isEmpty { Text("No Watch voice notes yet.") }
            ForEach(inbox.notes) { note in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hole \(note.hole)").font(.headline)
                    if note.roundID != rounds.activeRound?.id {
                        Text("This recording belongs to another round. It is retained here for later review.").font(.caption)
                    } else {
                        Button(busy == note.id ? "Transcribing…" : "Transcribe & Review") {
                            busy = note.id
                            Task { @MainActor in
                                defer { busy = nil }
                                do { review = WatchTranscript(hole: note.hole, text: try await OpenAIGolfService.transcribe(file: note.url)) }
                                catch { self.error = error.localizedDescription }
                            }
                        }.disabled(busy != nil)
                    }
                    Button("Remove recording", role: .destructive) { removing = note }.disabled(busy != nil)
                }
            }
        }
        .confirmationDialog("Remove this Watch recording?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let note = removing {
                    do { try FileManager.default.removeItem(at: note.url); inbox.reload() }
                    catch { self.error = error.localizedDescription }
                }
                removing = nil
            }
        }
        .navigationTitle("Watch voice notes")
        .onAppear { inbox.reload() }
        .sheet(item: $review) { item in HoleDictationView(holeNumber: item.hole, initialTranscript: item.text) }
        .alert("Couldn't transcribe", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "Try again.") }
    }
}
