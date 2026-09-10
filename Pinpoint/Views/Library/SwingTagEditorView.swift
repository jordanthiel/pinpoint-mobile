import SwiftUI

struct SwingTagEditorView: View {
    @Environment(SwingLibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    let swing: Swing

    @State private var customText = ""
    @State private var isDetecting = false

    private var current: Swing {
        library.swings.first(where: { $0.id == swing.id }) ?? swing
    }

    private var suggestedCustomTags: [SwingTag] {
        library.customTagsInLibrary.filter { candidate in
            !current.tags.contains(where: { $0.id == candidate.id })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ChipSection(
                        title: "Camera",
                        items: CameraAngle.allCases,
                        label: \.label,
                        systemImage: { $0.systemImage },
                        minimumChipWidth: 150,
                        isSelected: { current.tags.cameraAngle == $0 },
                        onTap: { angle in
                            toggle(angle.makeTag(source: .user))
                        }
                    )

                    ChipSection(
                        title: "Club",
                        items: ClubKind.allCases,
                        label: \.label,
                        minimumChipWidth: 100,
                        isSelected: { current.tags.clubKind == $0 },
                        onTap: { club in
                            toggle(club.makeTag(source: .user))
                        }
                    )

                    customSection

                    if current.hasLocalVideo {
                        Button {
                            Task { await detect() }
                        } label: {
                            HStack {
                                if isDetecting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "sparkle")
                                }
                                Text(isDetecting ? "Detecting…" : "Auto-detect from video")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(isDetecting)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(PinpointTheme.background)
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TAGS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PinpointTheme.secondaryText)

            HStack(spacing: 8) {
                TextField("Add a tag", text: $customText)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addCustomTag() }
                Button("Add") { addCustomTag() }
                    .font(.subheadline.weight(.semibold))
                    .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            let custom = current.tags.filter { $0.category == .custom }
            if !custom.isEmpty {
                FlowChipGrid(items: custom) { tag in
                    TagChip(
                        title: tag.label,
                        selected: true,
                        showsSparkle: tag.isAutomatic,
                        action: { remove(tag) }
                    )
                }
            }

            if !suggestedCustomTags.isEmpty {
                Text("From other swings")
                    .font(.caption)
                    .foregroundStyle(PinpointTheme.secondaryText)
                    .padding(.top, 4)
                FlowChipGrid(items: suggestedCustomTags) { tag in
                    TagChip(title: tag.label, selected: false) {
                        apply { $0.set(SwingTag(id: tag.id, label: tag.label, category: .custom, source: .user)) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle(_ tag: SwingTag) {
        apply { $0.toggle(tag) }
    }

    private func remove(_ tag: SwingTag) {
        apply { $0.removeTag(id: tag.id) }
    }

    private func addCustomTag() {
        guard let tag = SwingTag.custom(customText) else { return }
        apply { $0.set(tag) }
        customText = ""
    }

    private func apply(_ mutate: (inout [SwingTag]) -> Void) {
        var tags = current.tags
        mutate(&tags)
        library.updateTags(current, tags: tags)
    }

    private func detect() async {
        isDetecting = true
        defer { isDetecting = false }
        await library.detectTags(current)
    }
}
