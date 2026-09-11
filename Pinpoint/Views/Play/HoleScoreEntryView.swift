import SwiftUI

/// 18Birdies-style hole close-out: enter score / putts / penalties first,
/// then optionally map shots. Saving does not require any TrackedShots.
struct HoleScoreEntryView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    var holeNumber: Int
    var onFinished: (_ mapShots: Bool) -> Void = { _ in }

    @State private var score: Int = 4
    @State private var putts: Int = 2
    @State private var penalties: Int = 0
    @State private var fairway: FairwayPick = .na

    private enum FairwayPick: Hashable {
        case hit, miss, na

        var recorded: Bool? {
            switch self {
            case .hit: return true
            case .miss: return false
            case .na: return nil
            }
        }

        init(recorded: Bool?) {
            switch recorded {
            case true: self = .hit
            case false: self = .miss
            case nil: self = .na
            }
        }
    }

    private var holeDef: GolfHole? {
        rounds.activeRound?.hole(holeNumber)
    }

    private var hole: HoleScore? {
        rounds.activeRound?.score(for: holeNumber)
    }

    private var par: Int { holeDef?.par ?? 4 }
    private var yardage: Int { holeDef?.yardage ?? 0 }

    private var scoreChips: [Int] {
        HoleScore.scoreChipValues(par: par, current: score)
    }

    private var previewName: String {
        var hs = HoleScore(holeNumber: holeNumber)
        hs.applyRecordedScore(score: score, putts: putts, penalties: penalties, fairwayHit: fairway.recorded)
        return hs.scoreName(par: par)
    }

    private var previewGIR: Bool {
        (score - putts) <= max(1, par - 2)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        scoreSection
                        puttsSection
                        penaltiesSection
                        if par > 3 {
                            fairwaySection
                        }
                        derivedLine
                        saveRow
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Hole \(holeNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hole \(holeNumber)  ·  Par \(par)  ·  \(yardage) yds")
                .font(.title3.weight(.bold))
            Text(previewName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PlayUI.scoreColor(score: score, par: par))
        }
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Score").font(.headline)
                Spacer()
                HStack(spacing: 12) {
                    stepperButton(systemImage: "minus") {
                        score = max(1, score - 1)
                    }
                    Text("\(score)")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .frame(minWidth: 28)
                    stepperButton(systemImage: "plus") {
                        score += 1
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(scoreChips, id: \.self) { value in
                    chip(title: "\(value)", selected: score == value, accentPar: value == par) {
                        score = value
                    }
                }
            }
        }
    }

    private var puttsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Putts").font(.headline)
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { value in
                    chip(title: "\(value)", selected: putts == value) {
                        putts = value
                    }
                }
                chip(title: putts >= 4 ? "\(putts)+" : "4+", selected: putts >= 4) {
                    putts = putts >= 4 ? min(8, putts + 1) : 4
                }
            }
        }
    }

    private var penaltiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Penalties").font(.headline)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { value in
                    chip(title: "\(value)", selected: penalties == value) {
                        penalties = value
                    }
                }
            }
        }
    }

    private var fairwaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fairway").font(.headline)
            HStack(spacing: 8) {
                chip(title: "Hit", selected: fairway == .hit) { fairway = .hit }
                chip(title: "Miss", selected: fairway == .miss) { fairway = .miss }
                chip(title: "N/A", selected: fairway == .na) { fairway = .na }
            }
        }
    }

    private var derivedLine: some View {
        HStack(spacing: 8) {
            Image(systemName: previewGIR ? "checkmark.circle.fill" : "xmark.circle")
            Text(previewGIR ? "Green in regulation" : "Missed green in regulation")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(previewGIR ? Color(red: 0.18, green: 0.72, blue: 0.38) : PinpointTheme.secondaryText)
    }

    private var saveRow: some View {
        VStack(spacing: 10) {
            Button {
                commit()
                onFinished(false)
            } label: {
                Text("Save Score")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                commit()
                onFinished(true)
            } label: {
                Text("Add Shot Details")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())

            Text("Shots, clubs, and locations are optional. Save the number first.")
                .font(.caption)
                .foregroundStyle(PinpointTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
    }

    private func chip(title: String, selected: Bool, accentPar: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.monospacedDigit())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    selected ? PinpointTheme.accent.opacity(0.22) : PinpointTheme.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            selected ? PinpointTheme.accent
                                : (accentPar ? Color.white.opacity(0.28) : .clear),
                            lineWidth: selected ? 1.5 : 1
                        )
                )
                .foregroundStyle(selected ? PinpointTheme.accent : .white)
        }
        .buttonStyle(.plain)
    }

    private func stepperButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.bold))
                .frame(width: 36, height: 36)
                .background(PinpointTheme.surfaceElevated, in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func prefill() {
        guard let hole, let def = holeDef else {
            score = 4
            putts = 2
            return
        }
        if let recorded = hole.recordedScore {
            score = recorded
        } else if hole.hasScore {
            score = hole.grossScore
        } else {
            score = def.par
        }
        if let recorded = hole.recordedPutts {
            putts = recorded
        } else if hole.hasScore {
            putts = hole.putts
        } else {
            putts = 2
        }
        penalties = hole.penaltyStrokes
        if let recorded = hole.recordedFairwayHit {
            fairway = FairwayPick(recorded: recorded)
        } else if let fromShots = hole.fairwayHit(par: def.par) {
            fairway = FairwayPick(recorded: fromShots)
        } else {
            fairway = .na
        }
    }

    private func commit() {
        rounds.recordHoleScore(
            holeNumber,
            score: score,
            putts: putts,
            penalties: penalties,
            fairwayHit: par > 3 ? fairway.recorded : nil
        )
    }
}
