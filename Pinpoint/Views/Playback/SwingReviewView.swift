import SwiftUI

struct SwingCheckpoint: Codable {
    var frame: Int
    var time: Double
}

struct SavedSwingReview: Codable {
    var checkpoints: [String: SwingCheckpoint] = [:]
    var note = ""
}

/// The golfer marks observable events instead of relying on guessed impact frames.
struct SwingReviewControls: View {
    let swingID: UUID
    let frame: Int
    let time: Double
    let onSeek: (Int) -> Void
    @State private var review = SavedSwingReview()
    @State private var showReview = false
    @State private var saveError: String?
    private let phases = ["Takeaway", "Top", "Impact"]
    private var key: String { "pinpoint.swing.review.\(swingID.uuidString)" }
    private var tempo: Double? {
        guard let start = review.checkpoints["Takeaway"], let top = review.checkpoints["Top"], let impact = review.checkpoints["Impact"],
              top.time > start.time, impact.time > top.time else { return nil }
        return (top.time - start.time) / (impact.time - top.time)
    }

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(phases, id: \.self) { phase in
                    Button("Mark \(phase.lowercased()) here") {
                        review.checkpoints[phase] = SwingCheckpoint(frame: frame, time: time)
                        save()
                    }
                }
            } label: {
                Label("Mark frame", systemImage: "bookmark").font(.subheadline.bold())
            }
            Spacer()
            Button { showReview = true } label: {
                Label("Swing review · \(review.checkpoints.count)/3", systemImage: "waveform.path.ecg").font(.subheadline.bold())
            }
        }.padding(.horizontal, 18).padding(.vertical, 12).background(PinpointTheme.surface)
            .onAppear {
                if let data = UserDefaults.standard.data(forKey: key), let value = try? JSONDecoder().decode(SavedSwingReview.self, from: data) { review = value }
            }
            .sheet(isPresented: $showReview) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("See what your swing is doing.").font(.largeTitle.bold())
                            Text("Scrub the video and mark takeaway, the top of your backswing, and impact. Turn on the skeleton and angles from the video’s view controls to inspect body positions.")
                                .foregroundStyle(PinpointTheme.secondaryText)
                            ForEach(phases, id: \.self) { phase in
                                PlayUI.card {
                                    HStack {
                                        Text(phase).font(.headline)
                                        Spacer()
                                        if let checkpoint = review.checkpoints[phase] {
                                            Button("Frame \(checkpoint.frame + 1)") { onSeek(checkpoint.frame); showReview = false }
                                        } else { Text("Not marked").font(.caption).foregroundStyle(PinpointTheme.secondaryText) }
                                    }
                                    Text(cue(phase)).font(.subheadline).foregroundStyle(PinpointTheme.secondaryText)
                                }
                            }
                            PlayUI.card {
                                Label("Swing tempo", systemImage: "metronome").font(.headline)
                                if let tempo {
                                    Text(String(format: "%.2f : 1", tempo)).font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(PinpointTheme.accent)
                                    Text("Backswing time ÷ downswing time, from your marked frames. Compare swings recorded at the same frame rate and angle.").font(.subheadline).foregroundStyle(PinpointTheme.secondaryText)
                                } else {
                                    Text(review.checkpoints.count == 3 ? "Markers are out of order. Set takeaway before the top, and impact after the top." : "Mark all three phases to calculate your tempo.")
                                        .font(.subheadline).foregroundStyle(PinpointTheme.secondaryText)
                                }
                            }
                            PlayUI.card {
                                Text("One thing to take to practice").font(.headline)
                                TextField("What do you want to repeat or work on?", text: $review.note, axis: .vertical).lineLimit(3...6)
                                Text("Video angles are 2D observations, not measurements of club path or ball flight. Use a consistent camera position when comparing sessions.")
                                    .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                            }
                            if let saveError { Text(saveError).foregroundStyle(.red) }
                            Button("Reset phase markers", role: .destructive) { review.checkpoints = [:]; save() }
                        }.padding(20)
                    }.background(PinpointTheme.background).navigationTitle("Swing review").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { save(); showReview = false } } }
                        .onChange(of: review.note) { _, _ in save() }
                }
            }
    }
    private func cue(_ phase: String) -> String {
        switch phase {
        case "Takeaway": return "The first frame where the club moves away from address. Check posture and how your hands begin moving."
        case "Top": return "The frame where the backswing changes direction. Compare arm position and balance across your swings."
        default: return "The frame nearest ball contact. Compare your body position with address, then watch whether you finish in balance."
        }
    }
    private func save() {
        do { UserDefaults.standard.set(try JSONEncoder().encode(review), forKey: key); saveError = nil }
        catch { saveError = "Couldn't save your review. Please try again." }
    }
}
