import Foundation
import CryptoKit

enum CompanionRevision {
    static func of(_ hole: HoleScore) -> String {
        var hole = hole
        hole.locationSamples = nil // GPS is not a score edit or a Watch conflict.
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: (try? encoder.encode(hole)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
}
extension RoundStore {
    /// Idempotent absolute-score command with optimistic concurrency protection.
    func applyCompanionEdit(_ edit: CompanionScoreEdit) -> String? {
        guard let round = activeRound, round.id == edit.roundID, let hole = round.score(for: edit.hole) else {
            return "This round is no longer active. Refresh from iPhone."
        }
        if round.companionCommandIDs?.contains(edit.id) == true { return nil }
        guard CompanionRevision.of(hole) == edit.revision else {
            return "This hole changed on iPhone. Close and reopen the score editor."
        }
        guard saveScoreEntry(edit.hole, score: edit.score, putts: edit.putts, penalties: edit.penalties, advance: edit.advance, commandID: edit.id) else { return lastError ?? "Couldn't save. Try again." }
        return nil
    }
}
