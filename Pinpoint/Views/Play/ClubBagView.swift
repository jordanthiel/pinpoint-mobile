import SwiftUI

/// Edit which clubs are in the bag and how far each one carries.
/// Those numbers drive the live club label on the GPS map.
struct ClubBagView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    @State private var showAdd = false
    @State private var yardsDraft: [GolfClub: String] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("These carries are what the map uses. Drag a target and the club updates with the yardage.")
                            .font(.subheadline)
                            .foregroundStyle(PinpointTheme.secondaryText)

                        ForEach(rounds.clubBag.displayClubs) { entry in
                            clubRow(entry)
                        }

                        Button {
                            showAdd = true
                        } label: {
                            Label("Add a club", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(rounds.clubBag.clubsNotInBag.isEmpty)

                        Button("Reset to a standard 14-club bag") {
                            rounds.resetClubBag()
                            yardsDraft = [:]
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PinpointTheme.accent)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("My Bag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        for club in yardsDraft.keys { commitYards(club) }
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                addClubSheet
                    .preferredColorScheme(.dark)
                    .presentationDetents([.medium])
            }
        }
    }

    private func clubRow(_ entry: ClubBagEntry) -> some View {
        let draft = Binding(
            get: { yardsDraft[entry.club] ?? "\(Int(entry.carryYards.rounded()))" },
            set: { yardsDraft[entry.club] = $0 }
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.club.shortName)
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(PinpointTheme.accent)
                    .frame(width: 40, alignment: .leading)
                Text(entry.club.displayName)
                    .font(.headline)
                Spacer()
                if !entry.club.isPutter {
                    Button {
                        rounds.removeClubFromBag(entry.club)
                        yardsDraft[entry.club] = nil
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }

            if entry.club.isPutter {
                Text("Putting — not used for full-shot recommendations")
                    .font(.caption)
                    .foregroundStyle(PinpointTheme.secondaryText)
            } else {
                HStack(spacing: 10) {
                    Button {
                        rounds.setBagCarry(entry.club, yards: entry.carryYards - 5)
                        yardsDraft[entry.club] = nil
                    } label: {
                        Image(systemName: "minus")
                            .font(.headline.weight(.bold))
                            .frame(width: 44, height: 44)
                            .background(PinpointTheme.surfaceElevated, in: Circle())
                    }
                    .buttonStyle(.plain)

                    TextField("Yds", text: draft)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .padding(.vertical, 8)
                        .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onSubmit { commitYards(entry.club) }

                    Text("Yds")
                        .font(.headline)
                        .foregroundStyle(PinpointTheme.secondaryText)

                    Button {
                        rounds.setBagCarry(entry.club, yards: entry.carryYards + 5)
                        yardsDraft[entry.club] = nil
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline.weight(.bold))
                            .frame(width: 44, height: 44)
                            .background(PinpointTheme.surfaceElevated, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var addClubSheet: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                List {
                    ForEach(rounds.clubBag.clubsNotInBag) { club in
                        Button {
                            rounds.addClubToBag(club)
                            showAdd = false
                        } label: {
                            HStack {
                                Text(club.shortName)
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(PinpointTheme.accent)
                                    .frame(width: 40, alignment: .leading)
                                Text(club.displayName)
                                Spacer()
                                Text("\(Int(club.stockYards)) yds")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(PinpointTheme.secondaryText)
                            }
                        }
                        .listRowBackground(PinpointTheme.surface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAdd = false }
                }
            }
        }
    }

    private func commitYards(_ club: GolfClub) {
        guard let raw = yardsDraft[club], let value = Double(raw) else { return }
        rounds.setBagCarry(club, yards: value)
        yardsDraft[club] = nil
    }
}
