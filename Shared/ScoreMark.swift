import SwiftUI

/// Conventional scoring marks, shared by phone and Watch.
struct ScoreMark: View {
    var score: Int
    var par: Int
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            if score < par {
                Circle().stroke(lineWidth: 1.5)
                if score < par - 1 { Circle().inset(by: 4).stroke(lineWidth: 1) }
            } else if score > par {
                Rectangle().stroke(lineWidth: 1.5)
                if score > par + 1 { Rectangle().inset(by: 4).stroke(lineWidth: 1) }
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
