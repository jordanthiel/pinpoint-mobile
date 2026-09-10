import SwiftUI

struct PoseViewOptionsButton: View {
    @Binding var isOpen: Bool
    var isActive: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOpen.toggle()
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(isOpen || isActive ? PinpointTheme.accent : Color.white.opacity(0.12), in: Circle())
        }
        .accessibilityLabel("View options")
        .accessibilityValue(isOpen ? "Open" : "Closed")
    }
}

struct PoseViewOptionsPanel: View {
    @Binding var showPose: Bool
    @Binding var showVideo: Bool
    @Binding var showAngles: Bool
    @Binding var visibleAngles: Set<PoseAngle>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("View")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PinpointTheme.secondaryText)
                    .textCase(.uppercase)

                toggleRow("Pose", systemImage: "figure.stand", isOn: $showPose)
                toggleRow("Video", systemImage: "video", isOn: $showVideo)
                toggleRow("Angles", systemImage: "angle", isOn: $showAngles)

                if showAngles {
                    Divider()
                        .overlay(PinpointTheme.hairline)

                    Text("Joints")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PinpointTheme.secondaryText)
                        .textCase(.uppercase)

                    ForEach(PoseAngle.allCases) { angle in
                        Toggle(isOn: angleBinding(angle)) {
                            Text(angle.title)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                        .tint(PinpointTheme.accent)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 220)
        .frame(maxHeight: 380)
        .fixedSize(horizontal: false, vertical: !showAngles)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PinpointTheme.hairline, lineWidth: 1)
        }
    }

    private func toggleRow(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
        }
        .tint(PinpointTheme.accent)
    }

    private func angleBinding(_ angle: PoseAngle) -> Binding<Bool> {
        Binding(
            get: { visibleAngles.contains(angle) },
            set: { enabled in
                if enabled {
                    visibleAngles.insert(angle)
                } else {
                    visibleAngles.remove(angle)
                }
            }
        )
    }
}
