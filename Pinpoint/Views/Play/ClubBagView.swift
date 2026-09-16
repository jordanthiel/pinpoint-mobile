import SwiftUI

/// Edit which clubs are in the bag, their names, and how far each carries.
struct ClubBagView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    @State private var showAdd = false
    @State private var showNFC = false
    @State private var editing: ClubBagEntry?

    var body: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Rename clubs for your set (4-hybrid, 60°, mini driver) and set each carry. The map uses these numbers.")
                            .font(.subheadline)
                            .foregroundStyle(PinpointTheme.secondaryText)

                        Button { showNFC = true } label: { Label("Set up NFC club tags", systemImage: "wave.3.right") }
                            .buttonStyle(SecondaryButtonStyle())

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

                        Button("Reset to a standard 14-club bag") {
                            rounds.resetClubBag()
                            editing = nil
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PinpointTheme.accentText)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("My Bag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showNFC) { NFCTagSetupView() }
            .sheet(isPresented: $showAdd) {
                addClubSheet
                    .preferredColorScheme(.light)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $editing) { entry in
                ClubEditorSheet(entry: entry) { updated in
                    rounds.updateBagEntry(updated)
                } onDelete: {
                    rounds.removeBagEntry(id: entry.id)
                }
                .preferredColorScheme(.light)
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func clubRow(_ entry: ClubBagEntry) -> some View {
        Button {
            editing = entry
        } label: {
            HStack(spacing: 12) {
                Text(entry.club.shortName)
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(PinpointTheme.accentText)
                    .frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.fullLabel)
                        .font(.headline)
                        .foregroundStyle(PinpointTheme.primaryText)
                    if entry.nickname?.isEmpty == false {
                        Text(entry.club.displayName)
                            .font(.caption)
                            .foregroundStyle(PinpointTheme.secondaryText)
                    }
                }
                Spacer()
                Text("\(Int(entry.carryYards.rounded())) yds")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(PinpointTheme.primaryText)
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(PinpointTheme.accentText)
            }
            .padding(14)
            .background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var addClubSheet: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                List {
                    ForEach(GolfClub.allCases) { club in
                        Button {
                            rounds.addClubToBag(club)
                            showAdd = false
                        } label: {
                            HStack {
                                Text(club.shortName)
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(PinpointTheme.accentText)
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
}

/// Rename, change type, and set carry for one bag slot.
struct ClubEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State var entry: ClubBagEntry
    var onSave: (ClubBagEntry) -> Void
    var onDelete: () -> Void

    @State private var name = ""
    @State private var yardsText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Name")
                            .font(.headline)
                        TextField("4 Hybrid, 60°, Mini driver…", text: $name)
                            .textInputAutocapitalization(.words)
                            .padding(12)
                            .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Text("Club type")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(GolfClub.allCases) { club in
                                    Button {
                                        entry.club = club
                                        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            name = club.displayName
                                        }
                                    } label: {
                                        Text(club.shortName)
                                            .font(.subheadline.weight(.bold).monospacedDigit())
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(entry.club == club ? PinpointTheme.accent : PinpointTheme.surfaceElevated,
                                                        in: Capsule())
                                            .foregroundStyle(entry.club == club ? PinpointTheme.primaryText : PinpointTheme.secondaryText)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Text("Carry")
                            .font(.headline)
                        HStack(spacing: 10) {
                            Button {
                                bump(-5)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.headline.weight(.bold))
                                    .frame(width: 44, height: 44)
                                    .background(PinpointTheme.surfaceElevated, in: Circle())
                            }
                            .buttonStyle(.plain)

                            TextField("Yds", text: $yardsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(.title.weight(.bold).monospacedDigit())
                                .padding(.vertical, 8)
                                .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                            Text("Yds")
                                .font(.headline)
                                .foregroundStyle(PinpointTheme.secondaryText)

                            Button {
                                bump(5)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.headline.weight(.bold))
                                    .frame(width: 44, height: 44)
                                    .background(PinpointTheme.surfaceElevated, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            commit()
                            onSave(entry)
                            dismiss()
                        } label: {
                            Text("Save club")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        if !entry.club.isPutter {
                            Button("Remove from bag", role: .destructive) {
                                onDelete()
                                dismiss()
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                name = entry.nickname ?? entry.club.displayName
                yardsText = "\(Int(entry.carryYards.rounded()))"
            }
        }
    }

    private func bump(_ delta: Double) {
        let current = Double(yardsText) ?? entry.carryYards
        let next = min(400, max(15, current + delta))
        entry.carryYards = next
        yardsText = "\(Int(next.rounded()))"
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.nickname = trimmed.isEmpty || trimmed == entry.club.displayName ? nil : trimmed
        if let value = Double(yardsText) {
            entry.carryYards = value
        }
    }
}
