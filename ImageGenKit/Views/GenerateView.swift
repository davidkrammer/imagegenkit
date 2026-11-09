import SwiftUI

/// Manual image generation panel (placeholder; being designed). Present it as a sheet:
/// `.sheet(isPresented: $show) { GenerateView(references: [url]) }`
struct GenerateView: View {
    var references: [URL] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Generate").font(.title2.weight(.semibold))
            Button("Close") { dismiss() }
        }
        .frame(width: 720, height: 560)
    }
}
