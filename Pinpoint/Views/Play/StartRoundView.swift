import SwiftUI

/// Pre-round setup: mirrors the reference flow (round type, scoring mode, tee).
struct StartRoundView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    let course: GolfCourse
    var onStarted: () -> Void = {}

    @State private var roundType: RoundType = .eighteen
    @State private var scoringMode: ScoringMode = .smart
    @State private var teeName = "Blue"
    @State private var startHole = 1

    var body: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Starting Round At")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PinpointTheme.secondaryText)
                        Text(course.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(PinpointTheme.accent)

                        startHolePicker

                        Text("Round Type")
                            .font(.headline)
                        HStack(spacing: 10) {
                            ForEach(RoundType.allCases) { type in
                                typeChip(type.label, selected: roundType == type) {
                                    roundType = type
                                    clampStartHole()
                                }
                            }
                        }

                        Text("Scoring Mode")
                            .font(.headline)
                        HStack(spacing: 10) {
                            typeChip(ScoringMode.classic.label, selected: scoringMode == .classic) {
                                scoringMode = .classic
                            }
                            typeChip("Smart Tracking", selected: scoringMode == .smart, featured: true) {
                                scoringMode = .smart
                            }
                        }
                        Text("Smart Tracking auto-tracks shots from your watch and turns end-of-hole dictations into club, contact and shape data.")
                            .font(.footnote)
                            .foregroundStyle(PinpointTheme.secondaryText)

                        Text("Tee Selection")
                            .font(.headline)
                        ForEach(course.tees, id: \.name) { tee in
                            teeRow(tee)
                        }

                        Button {
                            rounds.startRound(course: course, teeName: teeName,
                                              roundType: roundType, scoringMode: scoringMode,
                                              startHole: startHole)
                            dismiss()
                            // Let the sheet dismiss before pushing the GPS view.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                onStarted()
                            }
                        } label: {
                            Label("Start Round", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New Round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var validStartHoles: [Int] {
        switch roundType {
        case .eighteen: return Array(1...18)
        case .front9: return Array(1...9)
        case .back9: return Array(10...18)
        }
    }

    private func clampStartHole() {
        if !validStartHoles.contains(startHole) {
            startHole = validStartHoles.first ?? 1
        }
    }

    private var startHolePicker: some View {
        HStack {
            Text("Starting from")
                .font(.headline)
            Spacer()
            Picker("Start hole", selection: $startHole) {
                ForEach(validStartHoles, id: \.self) { n in
                    Text("Hole \(n)").tag(n)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func typeChip(_ title: String, selected: Bool, featured: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(selected ? PinpointTheme.accent.opacity(0.2) : PinpointTheme.surfaceElevated,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(selected ? PinpointTheme.accent : .clear, lineWidth: 1.5)
                }
                .foregroundStyle(selected ? PinpointTheme.accent : .white)
        }
        .buttonStyle(.plain)
    }

    private func teeRow(_ tee: CourseTee) -> some View {
        Button {
            teeName = tee.name
        } label: {
            HStack {
                Circle()
                    .fill(teeColor(tee.name))
                    .frame(width: 14, height: 14)
                Text(tee.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(tee.totalYardage) yds · \(tee.slope)/\(String(format: "%.1f", tee.rating))")
                    .font(.caption)
                    .foregroundStyle(PinpointTheme.secondaryText)
                Image(systemName: teeName == tee.name ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(teeName == tee.name ? PinpointTheme.accent : PinpointTheme.secondaryText)
            }
            .padding(12)
            .background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func teeColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "blue": return .blue
        case "white": return .white
        case "red": return .red
        default: return .gray
        }
    }
}
