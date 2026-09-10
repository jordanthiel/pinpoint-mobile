import SwiftUI

struct AnnotationToolbarView: View {
    @Binding var tool: AnnotationTool
    @Binding var colorHex: String
    @Binding var isExpanded: Bool
    let canUndo: Bool
    let onUndo: () -> Void
    let onClear: () -> Void

    private let colors = ["FFFFFF", "0D5DE5", "F5D76E", "FF4D4D", "5AC8FA"]

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                    if isExpanded {
                        if case .none = tool {
                            tool = .draw(.pen)
                        }
                    } else {
                        tool = .none
                    }
                }
            } label: {
                Image(systemName: isExpanded ? "xmark" : "pencil")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(isExpanded ? PinpointTheme.accent : Color.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel(isExpanded ? "Close editor" : "Edit")

            if isExpanded {
                expandedTools
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
    }

    private var expandedTools: some View {
        VStack(spacing: 8) {
            ForEach(AnnotationKind.allCases) { kind in
                toolButton(kind)
            }

            VStack(spacing: 6) {
                ForEach(colors, id: \.self) { hex in
                    Button {
                        colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 14, height: 14)
                            .overlay {
                                Circle()
                                    .stroke(Color.white, lineWidth: colorHex == hex ? 2 : 0)
                            }
                    }
                    .accessibilityLabel("Color \(hex)")
                }
            }

            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.footnote)
                    .foregroundStyle(canUndo ? .white : .white.opacity(0.3))
                    .frame(width: 32, height: 32)
            }
            .disabled(!canUndo)

            Button(role: .destructive, action: onClear) {
                Image(systemName: "trash")
                    .font(.footnote)
                    .foregroundStyle(canUndo ? .red.opacity(0.95) : .white.opacity(0.3))
                    .frame(width: 32, height: 32)
            }
            .disabled(!canUndo)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PinpointTheme.hairline, lineWidth: 1)
        }
        .onAppear {
            if case .none = tool {
                tool = .draw(.pen)
            }
        }
    }

    private func toolButton(_ kind: AnnotationKind) -> some View {
        let selected = tool == .draw(kind)
        return Button {
            tool = .draw(kind)
        } label: {
            Image(systemName: kind.systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(selected ? PinpointTheme.accent : Color.clear, in: Circle())
        }
        .accessibilityLabel(kind.title)
    }
}
