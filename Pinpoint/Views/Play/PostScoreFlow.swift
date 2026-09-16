import SwiftUI

/// One presentation owns every post-score step, preventing sheet-transition races.
struct PostScoreFlow: View {
    enum Step { case pin, putt, shots }
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss
    var holeNumber: Int
    var onNext: () -> Void
    @State private var step: Step = .pin
    @State private var editingScore = false
    @State private var returnToShots = false
    @State private var error: String?

    init(holeNumber: Int, initialStep: Step = .pin, onNext: @escaping () -> Void) {
        self.holeNumber = holeNumber
        self.onNext = onNext
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        Group {
            if let round = rounds.activeRound, let layout = round.playLayout(for: holeNumber), let hole = round.score(for: holeNumber) {
                let pin = round.pinCoordinate(for: holeNumber) ?? layout.pin
                if step == .shots {
                    HoleConfirmView(holeNumber: holeNumber, layout: layout, pin: pin, tee: layout.tee,
                        onEditPin: { returnToShots = true; step = .pin },
                        onEditScore: { editingScore = true }, onNext: onNext,
                        onMenu: { dismiss() },
                        onEditPutt: { returnToShots = true; step = .putt })
                } else {
                    GreenView(holeNumber: holeNumber, mode: step == .pin ? .pin : .putt,
                        layout: layout, pin: pin, firstPuttFeet: hole.firstPuttFeet,
                        onMovePin: { _ in },
                        onConfirmPin: { point in
                            if rounds.saveGreenPosition(holeNumber, point: point, isPin: true) { advance(hasPutts: hole.recordedPutts != 0) }
                            else { error = rounds.lastError ?? "Couldn't save the pin position." }
                        }, onConfirmPutt: { _ in },
                        onSkip: { advance(hasPutts: hole.recordedPutts != 0) },
                        firstPuttPosition: hole.firstPuttPosition,
                        onConfirmPuttPosition: { point in
                            if rounds.saveGreenPosition(holeNumber, point: point, isPin: false) { advance(hasPutts: true) }
                            else { error = rounds.lastError ?? "Couldn't save the first putt." }
                        })
                        .id(step == .pin ? "pin" : "putt")
                }
            } else {
                ContentUnavailableView("Hole map unavailable", systemImage: "map", description: Text("Your score is saved."))
                    .overlay(alignment: .bottom) { Button("Continue", action: onNext).padding() }
            }
        }
        .sheet(isPresented: $editingScore) {
            HoleScoreEntryView(holeNumber: holeNumber, onFinished: { editingScore = false },
                onSkip: { editingScore = false }, advancesOnSave: false)
                .preferredColorScheme(.light)
        }
        .alert("Position not saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "Try again.") }
    }
    private func advance(hasPutts: Bool) {
        if returnToShots { returnToShots = false; step = .shots }
        else if step == .pin && hasPutts { step = .putt }
        else { step = .shots }
    }
}
