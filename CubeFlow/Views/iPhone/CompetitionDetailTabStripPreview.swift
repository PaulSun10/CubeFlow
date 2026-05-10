import SwiftUI

struct CompetitionDetailTabStripPreviewHost: View {
    @State private var selection: CompetitionDetailTab = .schedule
    @State private var draggedMaskScale = 1.10
    @State private var showsMaskDebugOverlay = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mask scale")
                    Spacer()
                    Text(draggedMaskScale, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $draggedMaskScale, in: 1.0...1.5, step: 0.01)

                Toggle("Show mask debug", isOn: $showsMaskDebugOverlay)
            }
            .padding(20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            previewCard(title: "Competition Detail Tabs", languageCode: "en")
            previewCard(title: "中文", languageCode: "zh-Hans")
            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    private func previewCard(title: String, languageCode: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            CompetitionDetailTabStrip(
                tabs: CompetitionDetailTab.allCases,
                languageCode: languageCode,
                draggedMaskScale: draggedMaskScale,
                showsMaskDebugOverlay: showsMaskDebugOverlay,
                selection: $selection
            )
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct CompetitionDetailTabStrip_Previews: PreviewProvider {
    static var previews: some View {
        CompetitionDetailTabStripPreviewHost()
            .previewDisplayName("Competition Detail Tab Strip")
    }
}
