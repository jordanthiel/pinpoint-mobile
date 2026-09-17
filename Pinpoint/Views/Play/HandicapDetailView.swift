import SwiftUI

struct HandicapDetailView: View {
    @Environment(RoundStore.self) private var store
    private var estimate: HandicapEstimate { HandicapEstimate(rounds: store.pastRounds) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PlayUI.card {
                    Text("Estimated handicap").font(.headline)
                    Text(estimate.displayValue).font(.system(size: 56, weight: .semibold)).monospacedDigit()
                    Text(estimate.value == nil ? "Save \(max(0, 3 - estimate.entries.count)) more eligible 18-hole rounds to establish your estimate." : "Based on \(estimate.countingIDs.count) counting rounds from your latest \(estimate.entries.count) eligible rounds.")
                        .foregroundStyle(PinpointTheme.secondaryText)
                }
                PlayUI.card {
                    Text("How it works").font(.headline)
                    Text("We compare your saved gross scores with each tee’s course rating and slope, then use the lowest differentials from up to your latest 20 eligible rounds. At least three rounds are needed.")
                    Text("This is a Pinpoint estimate, not an official Handicap Index. Gross scores are not adjusted for maximum hole scores, playing conditions, exceptional scores or handicap caps.")
                        .font(.footnote).foregroundStyle(PinpointTheme.secondaryText)
                    Text("Nine-hole, partial and unrated rounds stay in your stats but are excluded here. Nine-hole handicapping requires additional expected-score data.")
                        .font(.footnote).foregroundStyle(PinpointTheme.secondaryText)
                    Link("USGA calculation guide", destination: URL(string: "https://www.usga.org/content/usga/home-page/handicapping/world-handicap-system/topics/handicap-index-calculation.html")!)
                        .font(.footnote)
                }
                PlayUI.card {
                    Text("Rounds behind your estimate").font(.headline)
                    if estimate.entries.isEmpty { Text("No eligible rounds yet.").foregroundStyle(PinpointTheme.secondaryText) }
                    ForEach(estimate.entries) { entry in
                        NavigationLink { RoundSummaryView(selectedRoundID: entry.round.id) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.round.courseName).font(.subheadline.weight(.semibold))
                                    Text("\(entry.round.startedAt.formatted(date: .abbreviated, time: .omitted)) · \(entry.round.teeName) · \(entry.round.totalGross) strokes")
                                        .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(String(format: "%.1f", entry.differential)).monospacedDigit()
                                    Text(estimate.countingIDs.contains(entry.id) ? "Counting" : "Differential")
                                        .font(.caption2).foregroundStyle(PinpointTheme.accentText)
                                }
                            }.padding(.vertical, 6)
                        }.buttonStyle(.plain)
                    }
                    if estimate.excludedCount > 0 {
                        Text("\(estimate.excludedCount) saved rounds excluded: incomplete, fewer than 18 scored holes, or missing tee ratings.")
                            .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                    }
                }
            }.padding(20).padding(.bottom, FloatingNavigation.clearance)
        }.background(PinpointTheme.background).navigationTitle("Handicap")
    }
}
