import SwiftUI

/// Per-shot editor: lie, penalty, club, distances, contact/shape/quality.
struct ShotEditorView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    var holeNumber: Int
    var holeYardage: Int
    var existing: TrackedShot?
    var suggested: TrackedShot? = nil
    var prefillStart: GeoPoint? = nil
    var prefillEnd: GeoPoint? = nil
    var onDeleteSuggestion: (() -> Void)?
    var onDone: () -> Void = {}
    @State private var movingLocation = false
    @State private var initialized = false
    @State private var saveError = false

    @State private var correctedStart: GeoPoint?
    @State private var lieEdited = false
    @State private var lie: Lie = .tee
    @State private var penalty: Int = 0
    @State private var club: GolfClub?
    @State private var clubSuggested = false
    @State private var actualDistance = ""
    @State private var distanceToPin = ""
    @State private var carry = ""
    @State private var includeTrue = true
    @State private var contact: Contact?
    @State private var shape: ShotShape = .straight
    @State private var quality: ShotQuality?
    @State private var note = ""

    private var isEditing: Bool { existing != nil }

    private var editorClubs: [GolfClub] {
        let bag = rounds.clubBag.displayClubs.map(\.club)
        if bag.isEmpty { return Array(GolfClub.allCases) }
        if let club, !bag.contains(club) { return bag + [club] }
        return bag
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if let start = correctedStart {
                            PositioningMap(initialPoint: start, distance: 350, locationTrail: rounds.locationTrail(holeNumber)) { _ in }
                                .overlay { PlacementMarker(symbol: "mappin", color: PinpointTheme.accent) }
                                .id(start)
                                .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 18))
                                .allowsHitTesting(false)
                                .accessibilityLabel("Shot location, movement trail and recorded stops")
                        }
                        if correctedStart != nil {
                            Button { movingLocation = true } label: {
                                Label("Move Shot Location", systemImage: "map.fill")
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }.buttonStyle(SecondaryButtonStyle())
                            if let start = correctedStart, let end = prefillEnd ?? existing?.end {
                                Text("Mapped distance: \(Int(start.yards(to: end).rounded())) yds")
                                    .font(.headline.monospacedDigit())
                            }
                        }
                        if isEditing || onDeleteSuggestion != nil {
                            Button("Delete Shot", role: .destructive) { deleteShot() }
                                .buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        lieSection
                        clubSection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Actual Distance").font(.headline)
                            TextField("Distance in yards", text: $actualDistance).keyboardType(.decimalPad)
                                .padding(12).background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                            Text("Calculated from mapped shot locations. Includes roll.").font(.caption).foregroundStyle(.secondary)
                            if clubSuggested { Text("Club suggested from distance · tap a club to change it").font(.caption).foregroundStyle(.secondary) }
                        }
                        distanceSection
                        detailSection(contactTitle: "Contact", selection: $contact,
                                      options: Contact.allCases, label: \.label)
                        detailSection(contactTitle: "Shape", selection: $shape,
                                      options: ShotShape.allCases, label: \.label)
                        detailSection(contactTitle: "Quality", selection: $quality,
                                      options: ShotQuality.allCases, label: \.label)
                        noteSection
                    }
                    .padding(20)
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveRow.padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.regularMaterial)
            }
            .navigationTitle(isEditing ? "Edit Shot" : "Add Shot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $movingLocation) {
                if let start = correctedStart {
                    ShotLocationEditor(initialPoint: start, locationTrail: rounds.locationTrail(holeNumber), endpoint: prefillEnd ?? existing?.end) { point in
                        correctedStart = point
                        updateMappedDistance(from: point)
                        if let pin = rounds.activeRound?.pinCoordinate(for: holeNumber) {
                            distanceToPin = String(Int(point.yards(to: pin).rounded()))
                        }
                    }
                }
            }
            .alert("Shot not saved", isPresented: $saveError) { Button("OK", role: .cancel) { } }
                message: { Text(rounds.lastError ?? "Try again.") }
            .onAppear(perform: prefill)
        }
    }

    private func deleteShot() {
        if let existing { rounds.deleteShot(holeNumber, id: existing.id) }
        else { onDeleteSuggestion?() }
        dismiss()
        onDone()
    }

    private func prefill() {
        guard !initialized else { return }
        initialized = true
        if let existing {
            correctedStart = existing.start ?? prefillStart
            lie = existing.lie
            club = existing.club
            clubSuggested = existing.clubWasSuggested == true
            contact = existing.contact
            shape = existing.shape ?? .straight
            quality = existing.quality
            includeTrue = existing.includeInTrueDistance
            if let start = correctedStart, let pin = rounds.activeRound?.pinCoordinate(for: holeNumber) {
                distanceToPin = String(Int(start.yards(to: pin).rounded()))
            } else if let d = existing.distanceToPinBeforeYards { distanceToPin = "\(Int(d))" }
            if let c = existing.carryYards { carry = "\(Int(c))" }
            note = existing.note
        } else if let round = rounds.activeRound {
            clubSuggested = true
            correctedStart = suggested?.start ?? rounds.suggestedStop(holeNumber) ?? prefillStart
            let ball = rounds.ballState(holeNumber)
            lie = ball.lie
            if let start = correctedStart, let pin = round.pinCoordinate(for: holeNumber) {
                distanceToPin = "\(Int(start.yards(to: pin).rounded()))"
            } else {
                distanceToPin = "\(Int(ball.distanceYards))"
            }
            if prefillStart != nil, prefillEnd != nil {
                // Map distance is not measured carry.
                includeTrue = false
            }
            let count = round.score(for: holeNumber)?.shots.count ?? 0
            if count == 0 {
                club = holeYardage > 220 ? .driver : .iron7
                lie = .tee
            } else {
                let wind = round.courseWind.flatMap { $0.isFresh() ? $0 : nil }
                let bearing = round.playLayout(for: holeNumber)?.headingDegrees ?? 0
                let helping = wind?.helping(toward: bearing) ?? 0
                let playsLike = CaddieEngine.playsLike(yards: ball.distanceYards,
                                                       windMph: wind?.mph ?? 0, windHelping: helping)
                club = CaddieEngine.recommendClub(for: playsLike, bag: rounds.clubBag)?.club
            }
        }
        if let start = correctedStart { updateMappedDistance(from: start) }
        else if let distance = existing?.mappedDistanceYards { actualDistance = String(Int(distance.rounded())) }
    }

    private func updateMappedDistance(from start: GeoPoint) {
        guard let end = prefillEnd ?? existing?.end else { return }
        let yards = start.yards(to: end)
        actualDistance = String(Int(yards.rounded()))
        if club == nil || clubSuggested {
            club = CaddieEngine.suggestedShotClub(for: yards, bag: rounds.clubBag)
            clubSuggested = true
        }
    }

    private var header: some View {
        HStack {
            Text("Shot \(existing?.number ?? suggested?.number ?? rounds.nextShotNumber(holeNumber))")
                .font(.headline)
            + Text("  (Distance to Pin)")
                .font(.subheadline)
                .foregroundStyle(PinpointTheme.secondaryText)
            Spacer()
            Text("\(distanceToPin.isEmpty ? "–" : distanceToPin) Yds")
                .font(.title3.weight(.bold).monospacedDigit())
        }
    }

    private var lieSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lie").font(.headline)
            HStack(spacing: 8) {
                ForEach([Lie.tee, .fairway, .sand, .rough, .recovery], id: \.self) { l in
                    lieButton(l)
                }
            }
            HStack(spacing: 8) {
                ForEach([Lie.fringe, .green], id: \.self) { l in
                    lieButton(l)
                }
                Spacer()
            }
        }
    }

    private func lieButton(_ l: Lie) -> some View {
        Button {
            lie = l
            lieEdited = true
            if l == .green { club = .putter }
        } label: {
            VStack(spacing: 6) {
                Text(l.code)
                    .font(.headline.weight(.bold))
                    .frame(width: 52, height: 52)
                    .background(lie == l ? .white : PinpointTheme.surfaceElevated, in: Circle())
                    .overlay(Circle().stroke(lie == l ? PinpointTheme.accent : PinpointTheme.hairline, lineWidth: 1.5))
                    .foregroundStyle(lie == l ? PinpointTheme.accent : PinpointTheme.primaryText)
                Text(l.label)
                    .font(.caption2)
                    .foregroundStyle(PinpointTheme.secondaryText)
            }
        }
        .buttonStyle(.plain)
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
                    Button("Driver / Woods") { clubSuggested = false; club = .driver }
                    Button("Long iron / Hybrid") { clubSuggested = false; club = .iron5 }
                    Button("Short iron / Wedge") { clubSuggested = false; club = .pitchingWedge }
                    Button("Putter") { clubSuggested = false; club = .putter }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(PinpointTheme.accentText)
                }
            }
            if let club {
                Text(rounds.clubBag.entry(for: club)?.fullLabel ?? club.displayName)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(PinpointTheme.accentText)
                    .frame(maxWidth: .infinity)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(editorClubs) { c in
                        Button {
                            clubSuggested = false
                            club = c
                            if c.isPutter { lie = .green }
                        } label: {
                            Text(rounds.clubBag.entry(for: c)?.shortLabel ?? c.shortName)
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .frame(minWidth: 52)
                                .padding(.vertical, 10)
                                .background(club == c ? PinpointTheme.accent : PinpointTheme.surfaceElevated,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundStyle(club == c ? PinpointTheme.primaryText : PinpointTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let club {
                Text("Bag \(Int(rounds.bagCarry(for: club))) yds")
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
                    .font(.title3.weight(.bold).monospacedDigit())
            }
            TextField("Carry yards", text: $carry)
                .keyboardType(.numberPad)
                .padding(12)
                .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Toggle("Include this shot in True Distance?", isOn: $includeTrue)
                .font(.subheadline)
            if let start = correctedStart ?? existing?.start ?? prefillStart, let end = existing?.end ?? prefillEnd {
                Text("Mapped \(Int(start.yards(to: end).rounded())) yds from the satellite drop.")
                    .font(.caption)
                    .foregroundStyle(PinpointTheme.secondaryText)
            }
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
                                .foregroundStyle(selection.wrappedValue == opt ? PinpointTheme.accent : PinpointTheme.primaryText)
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
                                .foregroundStyle(selection.wrappedValue == opt ? PinpointTheme.accent : PinpointTheme.primaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note").font(.headline)
            Text("Unstructured color from dictation lives here for later analysis.")
                .font(.caption)
                .foregroundStyle(PinpointTheme.secondaryText)
            TextField("Missed high side, left or right, …", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .padding(12)
                .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var saveRow: some View {
        Button {
            let start = correctedStart ?? existing?.start ?? prefillStart
            let end = existing?.end ?? prefillEnd
            let computedCarry = Double(carry)
            var shot = TrackedShot(
                id: existing?.id ?? suggested?.id ?? UUID(),
                number: existing?.number ?? suggested?.number ?? rounds.nextShotNumber(holeNumber),
                club: club,
                lie: lie,
                distanceToPinBeforeYards: Double(distanceToPin),
                carryYards: computedCarry,
                start: start,
                end: end,
                contact: contact,
                shape: shape,
                quality: quality,
                includeInTrueDistance: includeTrue,
                source: existing?.source ?? .manual,
                timestamp: existing?.timestamp ?? Date(),
                note: note
            )
            shot.lieWasInferred = lieEdited ? false : (existing?.lieWasInferred ?? (existing == nil ? true : nil))
            shot.nfcTagID = existing?.nfcTagID
            shot.bagEntryID = existing?.bagEntryID
            shot.observations = existing?.observations
            shot.traveledYards = existing?.traveledYards
            shot.mappedDistanceYards = Double(actualDistance)
            shot.clubWasSuggested = clubSuggested
            shot.remainingFeet = existing?.remainingFeet
            if existing != nil {
                guard rounds.updateShot(holeNumber, shot) else { saveError = true; return }
            } else if suggested != nil, let start {
                guard rounds.moveShot(holeNumber, shot: shot, to: start) else { saveError = true; return }
            } else {
                guard rounds.addShot(holeNumber, shot) else { saveError = true; return }
            }
            dismiss()
            onDone()
        } label: {
            Text(isEditing ? "Save Changes" : "Save Shot")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(club == nil)
    }
}
