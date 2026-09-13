import SwiftUI

/// 18Birdies-style hole close-out sheet: light card with a score tile grid
/// (golf circle/square glyphs), putts row, and a Finish Hole advance.
/// Saving writes the card score/putts; penalties and fairway stay untouched.
struct HoleScoreEntryView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    var holeNumber: Int
    var onFinished: () -> Void = {}

    @State private var score: Int = 4
    @State private var putts: Int = 2
    @State private var showExtendedScores = false

    private var holeDef: GolfHole? {
        rounds.activeRound?.hole(holeNumber)
    }

    private var hole: HoleScore? {
        rounds.activeRound?.score(for: holeNumber)
    }

    private var par: Int { holeDef?.par ?? 4 }

    private var scoreValues: [Int] {
        showExtendedScores ? Array(1...12) : Array(1...9)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Hole \(holeNumber)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.black)

                        scoreSection

                        Divider()

                        puttsSection

                        bottomRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Score")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                Spacer()
                Button(showExtendedScores ? "Less" : "Others") {
                    showExtendedScores.toggle()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.1, green: 0.4, blue: 1.0))
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(scoreValues, id: \.self) { value in
                    scoreTile(value)
                }
            }
        }
    }

    private func scoreTile(_ value: Int) -> some View {
        Button {
            score = value
        } label: {
            ZStack {
                if value == par {
                    VStack(spacing: 0) {
                        Text("\(value)")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.black)
                        Text("Par")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.55))
                    }
                } else {
                    scoreGlyph(value)
                    Text("\(value)")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.black)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                score == value ? Color(red: 0.85, green: 0.91, blue: 1.0) : Color(red: 0.94, green: 0.96, blue: 0.98),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    /// Golf scoring glyphs: circles under par, squares over par, doubled for
    /// eagle-or-better / double-bogey-or-worse.
    private func scoreGlyph(_ value: Int) -> some View {
        Group {
            if value < par - 1 {
                doubleCircle
            } else if value == par - 1 {
                singleCircle
            } else if value == par + 1 {
                singleSquare
            } else {
                doubleSquare
            }
        }
    }

    private var glyphStroke: some ShapeStyle {
        Color.black.opacity(0.35)
    }

    private var singleCircle: some View {
        Circle().stroke(glyphStroke, lineWidth: 1.5).frame(width: 46, height: 46)
    }

    private var doubleCircle: some View {
        ZStack {
            Circle().stroke(glyphStroke, lineWidth: 1.5).frame(width: 48, height: 48)
            Circle().stroke(glyphStroke, lineWidth: 1).frame(width: 42, height: 42)
        }
    }

    private var singleSquare: some View {
        Rectangle().stroke(glyphStroke, lineWidth: 1.5).frame(width: 44, height: 44)
    }

    private var doubleSquare: some View {
        ZStack {
            Rectangle().stroke(glyphStroke, lineWidth: 1.5).frame(width: 46, height: 46)
            Rectangle().stroke(glyphStroke, lineWidth: 1).frame(width: 40, height: 40)
        }
    }

    private var puttsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Putts")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
            HStack(spacing: 10) {
                ForEach(0...4, id: \.self) { value in
                    Button {
                        putts = value
                    } label: {
                        Text("\(value)")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 62)
                            .background(
                                putts == value ? Color(red: 0.85, green: 0.91, blue: 1.0) : Color(red: 0.94, green: 0.96, blue: 0.98),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var bottomRow: some View {
        HStack {
            Spacer()
            VStack(spacing: 2) {
                Text("Hole \(holeNumber)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                Button("Finish Hole") {
                    commit()
                    onFinished()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.1, green: 0.4, blue: 1.0))
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                commit()
                onFinished()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 64, height: 64)
                    .background(Color(red: 0.9, green: 0.94, blue: 1.0), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
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
    }

    private func commit() {
        rounds.updateHole(holeNumber) {
            $0.recordedScore = max(1, score)
            $0.recordedPutts = max(0, putts)
            $0.isComplete = true
        }
    }
}
