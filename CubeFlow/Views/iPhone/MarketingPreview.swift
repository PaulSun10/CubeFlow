#if DEBUG && os(iOS)
import CoreData
import Combine
import SwiftUI

enum MarketingPreviewScrambles {
    static let threeByThree = [
        "F' D2 B' R2 F2 L2 F' D2 F' U2 F R D2 R' F2 D L2 F' R",
        "U D' L' F L2 U' L2 B D2 R2 D' F2 D' F2 R2 B2 U F2 L",
        "F2 L2 D2 L F2 L2 D2 B R' D' L2 R B' U2 B L' D2 F",
        "B' U' L2 B' U2 B D2 F2 L2 F' L2 D' L' F D U' B R F' U2",
        "U' B R2 D2 F2 D2 R' F D2 L' B2 L U2 R F U'"
    ]
}

enum MarketingPreviewPreset: String, CaseIterable, Identifiable {
    case timerThreeByThreeHero

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timerThreeByThreeHero: "Timer — 3×3 Hero"
        }
    }

    var timerConfiguration: MarketingTimerPreviewConfiguration {
        switch self {
        case .timerThreeByThreeHero:
            MarketingTimerPreviewConfiguration(
                event: .threeByThree,
                elapsedSeconds: 9.51,
                scramble: MarketingPreviewScrambles.threeByThree[0],
                fixedScrambleIndex: 0,
                mean: 10.9275,
                ao5: 10.24,
                ao12: 10.71,
                ao100: 10.84
            )
        }
    }
}

struct MarketingTimerPreviewConfiguration {
    var event: PuzzleEvent
    var elapsedSeconds: Double
    var scramble: String
    var fixedScrambleIndex: Int
    var mean: Double
    var ao5: Double
    var ao12: Double
    var ao100: Double

    mutating func advanceFixedScramble() -> String? {
        guard event == .threeByThree,
              !MarketingPreviewScrambles.threeByThree.isEmpty else { return nil }
        fixedScrambleIndex = (fixedScrambleIndex + 1) % MarketingPreviewScrambles.threeByThree.count
        scramble = MarketingPreviewScrambles.threeByThree[fixedScrambleIndex]
        return scramble
    }
}

private struct IsMarketingPreviewEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isMarketingPreview: Bool {
        get { self[IsMarketingPreviewEnvironmentKey.self] }
        set { self[IsMarketingPreviewEnvironmentKey.self] = newValue }
    }
}

@MainActor
final class MarketingPreviewEnvironment: ObservableObject {
    let persistenceController: PersistenceController
    let defaults: UserDefaults

    private let defaultsSuiteName: String

    init(preset: MarketingPreviewPreset) {
        let suiteName = "com.cubeflow.marketing-preview.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated Marketing Preview defaults")
        }

        defaults.removePersistentDomain(forName: suiteName)
        let persistenceController = PersistenceController(inMemory: true)

        self.defaultsSuiteName = suiteName
        self.defaults = defaults
        self.persistenceController = persistenceController

        Self.configure(defaults: defaults, preset: preset)
        Self.seed(
            context: persistenceController.container.viewContext,
            defaults: defaults,
            preset: preset
        )
    }

    deinit {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    private static func configure(defaults: UserDefaults, preset: MarketingPreviewPreset) {
        defaults.set("en", forKey: "appLanguage")
        defaults.set(SolveTimeAccuracy.hundredths.rawValue, forKey: "timerAccuracy")
        defaults.set(AverageDisplayOption.ao5AndAo12.rawValue, forKey: "averageDisplayOption")
        defaults.set("timer", forKey: "enteringTimesWith")
        defaults.set(false, forKey: "hideElementsWhenSolving")
        defaults.set(TimerFontDesignOption.serif.rawValue, forKey: "timerTextFontDesign")
        defaults.set(TimerFontDesignOption.serif.rawValue, forKey: "scrambleTextFontDesign")
        defaults.set(TimerFontDesignOption.serif.rawValue, forKey: "averageTextFontDesign")
        defaults.set(TimerFontWeightOption.semibold.rawValue, forKey: "timerTextFontWeight")
        defaults.set(TimerFontWeightOption.medium.rawValue, forKey: "scrambleTextFontWeight")
        defaults.set(TimerFontWeightOption.medium.rawValue, forKey: "averageTextFontWeight")
        defaults.set(DrawScramblePlacement.bottomRight.rawValue, forKey: "drawScramblePlacement")
        defaults.set(132.0, forKey: "drawScrambleFloatingSize")
    }

    private static func seed(
        context: NSManagedObjectContext,
        defaults: UserDefaults,
        preset: MarketingPreviewPreset
    ) {
        let configuration = preset.timerConfiguration
        let session = Session(
            name: "Marketing Preview",
            createdAt: .now,
            selectedEventRawValue: configuration.event.rawValue,
            context: context
        )
        session.id = UUID(uuidString: "D4F84CE1-5A61-4AC1-9F97-31AA8C4133A1")!
        defaults.set(session.id.uuidString, forKey: "selectedSessionID")

        let heroTimes = [
            9.51, 10.20, 10.24, 10.28, 11.50,
            10.60, 10.70, 10.80, 10.90, 10.94, 10.94, 12.00
        ]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let todayAnchor = calendar.date(byAdding: .hour, value: 12, to: today) ?? .now

        for (index, time) in heroTimes.enumerated() {
            let solve = Solve(
                time: time,
                date: todayAnchor.addingTimeInterval(TimeInterval(-index)),
                scramble: configuration.scramble,
                event: configuration.event.rawValue,
                session: session,
                context: context
            )
            solve.id = deterministicSolveID(index: index)
        }

        for dayOffset in 1...16 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: todayAnchor) else { continue }
            let solve = Solve(
                time: 11.0 + Double(dayOffset) / 100,
                date: date,
                scramble: configuration.scramble,
                event: configuration.event.rawValue,
                session: session,
                context: context
            )
            solve.id = deterministicSolveID(index: heroTimes.count + dayOffset - 1)
        }

        do {
            try context.save()
        } catch {
            fatalError("Could not seed Marketing Preview: \(error)")
        }
    }

    private static func deterministicSolveID(index: Int) -> UUID {
        let suffix = String(format: "%012X", index + 1)
        return UUID(uuidString: "00000000-0000-4000-8000-\(suffix)")!
    }
}

struct MarketingPreviewCatalogView: View {
    @State private var selectedPreset: MarketingPreviewPreset?

    var body: some View {
        List {
            Section {
                ForEach(MarketingPreviewPreset.allCases) { preset in
                    Button {
                        selectedPreset = preset
                    } label: {
                        HStack {
                            Label(preset.title, systemImage: "camera.viewfinder")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Uses isolated in-memory data and temporary settings. Triple-tap to reveal the exit button after it hides.")
            }
        }
        .navigationTitle("Marketing Preview")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedPreset) { preset in
            MarketingPreviewHost(preset: preset)
        }
    }
}

private struct MarketingPreviewHost: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var previewEnvironment: MarketingPreviewEnvironment
    @State private var configuration: MarketingTimerPreviewConfiguration
    @State private var showsExitButton = true
    @State private var showsConfiguration = false
    @State private var controlsWereManuallyToggled = false

    private let preset: MarketingPreviewPreset

    init(preset: MarketingPreviewPreset) {
        self.preset = preset
        _previewEnvironment = StateObject(wrappedValue: MarketingPreviewEnvironment(preset: preset))
        _configuration = State(initialValue: preset.timerConfiguration)
    }

    var body: some View {
        IPhoneContentView(marketingPreviewConfiguration: $configuration)
            .environment(\.managedObjectContext, previewEnvironment.persistenceController.container.viewContext)
            .environment(\.solveTimeAccuracy, .hundredths)
            .environment(\.isMarketingPreview, true)
            .defaultAppStorage(previewEnvironment.defaults)
            .overlay(alignment: .topTrailing) {
                if showsExitButton {
                    HStack(spacing: 8) {
                        Button {
                            showsConfiguration = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .compatibleGlassFromIOS16(in: Circle())
                        }

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .compatibleGlassFromIOS16(in: Circle())
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    .padding(.trailing, 10)
                    .transition(.opacity)
                }
            }
            .sheet(isPresented: $showsConfiguration) {
                marketingPreviewConfigurationSheet
                    .compatibleMediumSheet()
            }
            .simultaneousGesture(
                TapGesture(count: 3).onEnded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsWereManuallyToggled = true
                        showsExitButton.toggle()
                    }
                }
            )
            .task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !controlsWereManuallyToggled else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsExitButton = false
                }
            }
    }

    private var marketingPreviewConfigurationSheet: some View {
        CompatibleNavigationContainer {
            Form {
                Section("Preview Values") {
                    previewValueField("Time", value: $configuration.elapsedSeconds)
                    previewValueField("Mean", value: $configuration.mean)
                    previewValueField("Ao5", value: $configuration.ao5)
                    previewValueField("Ao12", value: $configuration.ao12)
                    previewValueField("Ao100", value: $configuration.ao100)
                }
            }
            .navigationTitle("Marketing Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showsConfiguration = false
                    }
                }
            }
        }
    }

    private func previewValueField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(
                title,
                value: value,
                format: .number.precision(.fractionLength(0...3))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
        }
    }
}
#endif
