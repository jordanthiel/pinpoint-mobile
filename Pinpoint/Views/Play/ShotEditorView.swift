import SwiftUI

/// Per-shot editor: lie, penalty, club, distances, contact/shape/quality.
struct ShotEditorView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    var holeNumber: Int
    var holeYardage: Int
    var existing: TrackedShot?
    var onDone: () -> Void = {}

    @State private var lie: Lie = .tee
    @State private var penalty: Int = 0
    @State private var club: GolfClub?
    @State private var distanceToPin = ""
    @State private var carry = ""
    @State private var includeTrue = true
    @State private var contact: Contact?
    @State private var shape: ShotShape = .straight
    @State private var quality: ShotQuality?

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        lieSection
                        penaltySection
                        clubSection
                        distanceSection
                        detailSection(contactTitle: "Contact", selection: $contact,
                                      options: Contact.allCases, label: \.label)
                        detailSection(contactTitle: "Shape", selection: $shape,
                                      options: ShotShape.allCases, label: \.label)
                        detailSection(contactTitle: "Quality", selection: $quality,
                                      options: ShotQuality.allCases, label: \.label)
                        saveRow
                    }
                    .padding(20)
                }
            }
            .navigationTitle(isEditing ? "Edit Shot" : "Add Shot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) {
                            if let existing {
                                rounds.deleteShot(holeNumber, id: existing.id)
                            }
                            dismiss()
                            onDone()
                        }
                    }
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        if let existing {
            lie = existing.lie
            club = existing.club
            contact = existing.contact
            shape = existing.shape ?? .straight
            quality = existing.quality
            includeTrue = existing.includeInTrueDistance
            if let d = existing.distanceToPinBeforeYards { distanceToPin = "\(Int(d))" }
            if let c = existing.carryYards { carry = "\(Int(c))" }
        } else if let round = rounds.activeRound {
            let ball = rounds.ballState(holeNumber)
            lie = ball.lie
            distanceToPin = "\(Int(ball.distanceYards))"
            // Sensible default club for the number: driver off the first tee.
            let count = round.score(for: holeNumber)?.shots.count ?? 0
            if count == 0 {
                club = holeYardage > 220 ? .driver : .iron7
                lie = .tee
            } else {
                let helping = cos(Double(holeNumber) * 0.7)
                let playsLike = CaddieEngine.playsLike(yards: ball.distanceYards,
                                                       windMph: round.windMph, windHelping: helping)
                club = CaddieEngine.recommendClub(for: playsLike, averages: rounds.clubAverages())?.club
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Shot \(existing?.number ?? rounds.nextShotNumber(holeNumber)) · Hole \(holeNumber)")
                .font(.headline)
            Spacer()
            Text("\(distanceToPin.isEmpty ? "–" : distanceToPin) Yds to pin")
                .font(.headline.monospacedDigit())
        }
    }

    private var lieSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lie").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                ForEach(Lie.allCases) { l in
                    Button {
                        lie = l
                        if l == .green { club = .putter }
                    } label: {
                        VStack(spacing: 4) {
                            Text(l.code)
                                .font(.headline.weight(.bold))
                                .frame(width: 52, height: 52)
                                .background(lie == l ? PinpointTheme.accent.opacity(0.25) : PinpointTheme.surfaceElevated,
                                            in: Circle())
                                .overlay(Circle().stroke(lie == l ? PinpointTheme.accent : .clear, lineWidth: 2))
                                .foregroundStyle(lie == l ? PinpointTheme.accent : .white)
                            Text(l.label)
                                .font(.caption2)
                                .foregroundStyle(PinpointTheme.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var penaltySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Penalty").font(.headline)
            HStack(spacing: 10) {
                ForEach(0..<3) { p in
                    Button {
                        penalty = p
                    } label: {
                        Text("\(p)")
                            .font(.headline.monospacedDigit())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(penalty == p ? PinpointTheme.accent.opacity(0.2) : PinpointTheme.surfaceElevated,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(penalty == p ? PinpointTheme.accent : .clear, lineWidth: 1.5))
                            .foregroundStyle(penalty == p ? PinpointTheme.accent : PinpointTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var clubSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Select Club").font(.headline)
                Spacer()
                // Quick filter: long / mid / short.
                Menu {
                    Button("Driver / Woods") { club = .driver }
                    Button("Long iron / Hybrid") { club = .iron5 }
                    Button("Short iron / Wedge") { club = .pitchingWedge }
                    Button("Putter") { club = .putter }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(PinpointTheme.accent)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GolfClub.allCases) { c in
                        Button {
                            club = c
                            if c.isPutter { lie = .green }
                        } label: {
                            Text(c.shortName)
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .frame(minWidth: 52)
                                .padding(.vertical, 10)
                                .background(club == c ? PinpointTheme.accent : PinpointTheme.surfaceElevated,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundStyle(club == c ? .white : PinpointTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let club {
                Text("Stock ~\(Int(club.stockYards)) yds · personal \(rounds.clubAverages()[club].map { "\(Int($0)) yds" } ?? "–")")
                    .font(.caption)
                    .foregroundStyle(PinpointTheme.secondaryText)
            }
        }
    }

    private var distanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("True Distance").font(.headline)
                Spacer()
                Text("\(carry.isEmpty ? "–" : carry) Yds")
                    .font(.headline.monospacedDigit())
            }
            TextField("Carry yards", text: $carry)
                .keyboardType(.numberPad)
                .padding(12)
                .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            TextField("Distance to pin before shot", text: $distanceToPin)
                .keyboardType(.numberPad)
                .padding(12)
                .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Toggle("Include this shot in True Distance?", isOn: $includeTrue)
                .font(.subheadline)
        }
    }

    private func detailSection<T: Hashable>(contactTitle: String, selection: Binding<T?>,
                                            options: [T], label: KeyPath<T, String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(contactTitle).font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { opt in
                        Button {
                            selection.wrappedValue = (selection.wrappedValue == opt) ? nil : opt
                        } label: {
                            Text(opt[keyPath: label])
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selection.wrappedValue == opt ? PinpointTheme.accent.opacity(0.25) : PinpointTheme.surfaceElevated,
                                            in: Capsule())
                                .foregroundStyle(selection.wrappedValue == opt ? PinpointTheme.accent : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func detailSection<T: Hashable>(contactTitle: String, selection: Binding<T>,
                                            options: [T], label: KeyPath<T, String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(contactTitle).font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { opt in
                        Button {
                            selection.wrappedValue = opt
                        } label: {
                            Text(opt[keyPath: label])
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selection.wrappedValue == opt ? PinpointTheme.accent.opacity(0.25) : PinpointTheme.surfaceElevated,
                                            in: Capsule())
                                .foregroundStyle(selection.wrappedValue == opt ? PinpointTheme.accent : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var saveRow: some View {
        Button {
            let shot = TrackedShot(
                id: existing?.id ?? UUID(),
                number: existing?.number ?? rounds.nextShotNumber(holeNumber),
                club: club,
                lie: lie,
                distanceToPinBeforeYards: Double(distanceToPin),
                carryYards: Double(carry),
                contact: contact,
                shape: shape,
                quality: quality,
                includeInTrueDistance: includeTrue,
                source: existing?.source ?? .manual,
                timestamp: existing?.timestamp ?? Date()
            )
            if existing != nil {
                rounds.updateShot(holeNumber, shot)
            } else {
                rounds.addShot(holeNumber, shot)
            }
            if penalty > 0 {
                rounds.updateHole(holeNumber) { $0.penaltyStrokes += penalty }
            }
            dismiss()
            onDone()
        } label: {
            Text("Save")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(club == nil)
    }
}
