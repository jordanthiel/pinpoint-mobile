import SwiftUI
import UIKit

struct NFCTagSetupView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss
    @State private var reader = ClubNFCReader()
    @State private var status = "Choose a club, then scan its tag. Tags are read without changing their contents."
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Club tags").font(.title.bold())
                    Text(status).font(.subheadline).foregroundStyle(PinpointTheme.secondaryText)
                    Text(reader.message).font(.caption)
                    ForEach(rounds.clubBag.displayClubs) { club in
                        PlayUI.card {
                            HStack {
                                Text(club.fullLabel).font(.headline)
                                Spacer()
                                Text(club.nfcTagID == nil ? "Not linked" : "Linked").font(.caption)
                            }
                            Button(club.nfcTagID == nil ? "Assign tag" : "Replace tag") {
                                let owner = rounds.accountID
                                reader.scan(prompt: "Scan the tag for \(club.fullLabel)") { tag in
                                    guard rounds.accountID == owner else { status = "Account changed. Scan again."; return }
                                    if rounds.assignNFCTag(tag, to: club.id) {
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                        status = "Tag linked to \(club.fullLabel)."
                                    } else { status = rounds.lastError ?? "Could not save tag." }
                                }
                            }.disabled(reader.scanning)
                            if club.nfcTagID != nil {
                                Button("Unlink tag", role: .destructive) {
                                    status = rounds.assignNFCTag(nil, to: club.id) ? "Tag unlinked." : "Could not unlink tag."
                                }.disabled(reader.scanning)
                            }
                        }
                    }
                    Text("Use NTAG213, NTAG215, NTAG216 or ISO 15693 tags. Your club assignments sync with your bag.").font(.footnote)
                }.padding(20)
            }.background(PinpointTheme.background).navigationTitle("NFC setup")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onDisappear { reader.cancel() }
        }
    }
}

struct NFCShotLogView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss
    let holeNumber: Int
    @State private var reader = ClubNFCReader()
    @State private var location = PlayerLocation()
    @State private var status = "Scan the club where you take your shot."
    @State private var logged: TrackedShot?
    @State private var editing: TrackedShot?
    @State private var setup = false
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Label("Hole \(holeNumber) · Scan club", systemImage: "wave.3.right").font(.title2.bold())
                Text(status)
                Text(reader.message).font(.footnote).foregroundStyle(PinpointTheme.secondaryText)
                Button("Scan club tag", action: scan).buttonStyle(PrimaryButtonStyle()).disabled(reader.scanning)
                if let logged {
                    Button("Edit shot location & details") { editing = logged }
                    Button("Undo this shot", role: .destructive) {
                        rounds.deleteShot(holeNumber, id: logged.id)
                        if rounds.activeRound?.score(for: holeNumber)?.shots.contains(where: { $0.id == logged.id }) == false {
                            self.logged = nil; status = "Shot removed."
                        } else { status = "Could not remove shot. Try again." }
                    }
                }
                Button("Set up club tags") { setup = true }
                Text("Each scan counts one shot. Enter your final score when you finish the hole. Estimated locations can be adjusted on the map.")
                    .font(.footnote).foregroundStyle(PinpointTheme.secondaryText)
                Spacer()
            }.padding(20).background(PinpointTheme.background)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Back to play") { dismiss() } } }
                .sheet(isPresented: $setup) { NFCTagSetupView() }
                .sheet(item: $editing) { shot in ShotEditorView(holeNumber: holeNumber, holeYardage: rounds.activeRound?.hole(holeNumber)?.yardage ?? 0, existing: shot) }
                .onAppear { location.start() }
                .onDisappear { reader.cancel(); location.stop() }
                .onChange(of: rounds.accountID) { _, _ in reader.cancel(); dismiss() }
                .onChange(of: rounds.activeRound?.id) { _, _ in reader.cancel(); dismiss() }
        }
    }
    private func scan() {
        guard let roundID = rounds.activeRound?.id else { status = "Start a round first."; return }
        let owner = rounds.accountID
        reader.scan(prompt: "Hold your club tag near the top of your iPhone to log a shot.") { tag in
            guard rounds.accountID == owner, rounds.activeRound?.id == roundID else { status = "Round or account changed. Scan again."; return }
            if let shot = rounds.logNFCShot(tag: tag, roundID: roundID, hole: holeNumber, phonePoint: location.freshCoordinate) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                logged = shot; status = "Shot \(shot.number) saved. \(shot.note)"
            } else { status = rounds.lastError ?? "Shot was not saved." }
        }
    }
}
