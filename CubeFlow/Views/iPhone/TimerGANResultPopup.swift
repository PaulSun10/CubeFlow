import SwiftUI

#if os(iOS)
struct TimerGANResultPopup: View {
    let pendingSolveTime: Double?
    let inputMode: GANResultInputMode
    let choices: [SolveResult]
    let selectedResult: SolveResult
    let commitProgress: Double
    let autoCommitDelay: TimeInterval
    let onSave: (SolveResult) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("timer.solve_result.title")
                .font(.system(size: 17, weight: .semibold))

            Text(SolveMetrics.formatTime(pendingSolveTime ?? 0, decimals: 3))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)

            Text(inputMode.helpLocalizedKey)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ForEach(choices, id: \.rawValue) { result in
                    resultButton(for: result)
                }
            }

            Button(role: .cancel, action: onCancel) {
                Text("common.cancel")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground).opacity(0.78))
            )
        }
        .padding(20)
        .frame(maxWidth: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
    }

    private func resultButton(for result: SolveResult) -> some View {
        Button {
            onSave(result)
        } label: {
            HStack(spacing: 12) {
                Text(localizedResultTitle(for: result))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if selectedResult == result {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(Color.accentColor))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(resultButtonBackground(for: result))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selectedResult == result ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func resultButtonBackground(for result: SolveResult) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground).opacity(0.78))

            if selectedResult == result {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: proxy.size.width * commitProgress)
                }
                .animation(.linear(duration: autoCommitDelay), value: commitProgress)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func localizedResultTitle(for result: SolveResult) -> LocalizedStringKey {
        switch result {
        case .solved:
            return "common.solved"
        case .plusTwo:
            return "inspection.speech.plus_two"
        case .dnf:
            return "common.dnf"
        }
    }
}
#endif
