import SwiftUI

struct SwingLibraryView: View {
    @Environment(SwingLibraryStore.self) private var library
    @State private var showRecorder = false
    @State private var showAccount = false
    @State private var showFilters = false
    @State private var playbackSwing: Swing?
    @State private var capturedSwing: Swing?
    @State private var swingPendingDelete: Swing?
    @State private var renameTarget: Swing?
    @State private var renameText = ""
    @State private var tagEditorSwing: Swing?
    @State private var filter = LibraryFilter()

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var visibleSwings: [Swing] {
        library.swings.filter { filter.matches($0) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()

                if library.swings.isEmpty {
                    emptyState.padding(.bottom, FloatingNavigation.clearance)
                } else {
                    VStack(spacing: 0) {
                        LibraryFilterBar(
                            filter: $filter,
                            customTags: library.customTagsInLibrary,
                            onEdit: { showFilters = true }
                        )
                        if visibleSwings.isEmpty {
                            filteredEmptyState.padding(.bottom, FloatingNavigation.clearance)
                        } else {
                            swingGrid.contentMargins(.bottom, FloatingNavigation.clearance, for: .scrollContent)
                        }
                    }
                }
            }
            .navigationTitle("Swing studio").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            showAccount = true
                        } label: {
                            Image(systemName: library.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                        }
                        .accessibilityLabel("Cloud account")

                        Button {
                            Task { await library.refreshFromCloud() }
                        } label: {
                            if library.isSyncing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .accessibilityLabel("Sync from cloud")
                        .disabled(!library.isSignedIn)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showRecorder = true
                    } label: {
                        Image(systemName: "record.circle")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(PinpointTheme.accentText)
                    }
                    .accessibilityLabel("Record a swing")
                }
            }
            .fullScreenCover(isPresented: $showRecorder) {
                RecordSwingView { swing in
                    capturedSwing = swing
                    showRecorder = false
                }
            }
            .navigationDestination(item: $playbackSwing) { swing in
                SwingPlaybackView(swing: swing)
            }
            .onChange(of: showRecorder) { _, isShowing in
                if !isShowing, let swing = capturedSwing {
                    capturedSwing = nil
                    playbackSwing = swing
                }
            }
            .sheet(isPresented: Binding(
                get: { showAccount || library.needsAuth },
                set: { presented in
                    showAccount = presented
                    library.needsAuth = presented
                }
            )) {
                AccountView()
                    .preferredColorScheme(.light)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showFilters) {
                LibraryFilterSheet(filter: $filter, customTags: library.customTagsInLibrary)
                    .preferredColorScheme(.light)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $tagEditorSwing) { swing in
                SwingTagEditorView(swing: swing)
                    .preferredColorScheme(.light)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert("Delete this swing?", isPresented: Binding(
                get: { swingPendingDelete != nil },
                set: { if !$0 { swingPendingDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let swing = swingPendingDelete {
                        Task { await library.delete(swing) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It will be removed from this iPhone and from the cloud if it was uploaded.")
            }
            .alert("Rename swing", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Title", text: $renameText)
                Button("Save") {
                    if let swing = renameTarget {
                        library.rename(swing, to: renameText)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .task {
                await library.refreshFromCloud()
                await library.backfillAutoTags()
            }
            .overlay(alignment: .bottom) {
                if let message = library.lastError {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding()
                        .onTapGesture { library.lastError = nil }
                }
            }
        }
    }

    private var swingGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button { showRecorder = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Your next swing starts here.").font(.title2.bold())
                            Text("Capture • Slow motion • Pose • Tempo").font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "video.badge.plus").font(.title).foregroundStyle(PinpointTheme.accentText)
                    }.padding(18).background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(visibleSwings) { swing in
                    NavigationLink {
                        SwingPlaybackView(swing: swing)
                    } label: {
                        SwingCardView(swing: swing)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if swing.syncStatus == .local {
                            Button {
                                Task { await library.upload(swing) }
                            } label: {
                                Label("Upload to cloud", systemImage: "cloud")
                            }
                        }
                        if swing.syncStatus == .cloudOnly {
                            Button {
                                Task { await library.download(swing) }
                            } label: {
                                Label("Download", systemImage: "cloud")
                            }
                        }
                        Button {
                            tagEditorSwing = swing
                        } label: {
                            Label("Tags", systemImage: "tag")
                        }
                        Button {
                            renameTarget = swing
                            renameText = swing.title
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            swingPendingDelete = swing
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            }
            .padding(16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "figure.golf")
                .font(.system(size: 56))
                .foregroundStyle(PinpointTheme.accentText)
            Text("Build a swing you trust.")
                .font(.title2.weight(.semibold))
            Text("Record in extra slow motion, then scrub frame by frame and mark positions, lines, and angles.")
                .font(.body)
                .foregroundStyle(PinpointTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showRecorder = true
            } label: {
                Label("Record a swing", systemImage: "record.circle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 48)
            .padding(.top, 8)
        }
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40))
                .foregroundStyle(PinpointTheme.accentText)
            Text("No matching swings")
                .font(.title3.weight(.semibold))
            Text("Try a different date, camera view, club, or tag.")
                .font(.subheadline)
                .foregroundStyle(PinpointTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Clear filters") {
                filter.clear()
            }
            .font(.headline)
            .foregroundStyle(PinpointTheme.accentText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct SwingCardView: View {
    @Environment(SwingLibraryStore.self) private var library
    let swing: Swing

    private var current: Swing {
        library.swings.first(where: { $0.id == swing.id }) ?? swing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        Text(current.formattedDuration)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(8)
                    }

                Image(systemName: current.syncStatus.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.5), in: Circle())
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(current.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PinpointTheme.primaryText)
                .lineLimit(2)
            Text("\(current.resolutionLabel) · \(Int(current.frameRate.rounded())) FPS")
                .font(.caption)
                .foregroundStyle(PinpointTheme.secondaryText)

            if !current.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(current.tags.ordered) { tag in
                            TagChip(
                                title: tag.label,
                                selected: false,
                                compact: true,
                                showsSparkle: tag.isAutomatic
                            )
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var thumbnail: some View {
        let url = library.thumbnailURL(for: current)
        if current.syncStatus == .cloudOnly {
            ZStack {
                PinpointTheme.surfaceElevated
                VStack(spacing: 8) {
                    Image(systemName: "cloud")
                    Text("In the cloud")
                        .font(.caption)
                }
                .foregroundStyle(PinpointTheme.secondaryText)
            }
        } else if let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                PinpointTheme.surfaceElevated
                Image(systemName: "video")
                    .foregroundStyle(PinpointTheme.secondaryText)
            }
        }
    }
}
