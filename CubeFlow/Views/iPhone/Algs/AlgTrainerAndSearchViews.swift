import SwiftUI
import UIKit
import Combine

struct AlgRecognitionTrainerView: View {
    let title: String
    let scopeTitle: String
    let languageCode: String
    let setID: String
    let scopeID: String
    let level: AlgTrainerRecognitionLevel
    let seeds: [AlgTrainerQuestionSeed]

    @AppStorage("algTrainerAttemptStore") private var attemptStore: String = "[]"
    @Environment(\.dismiss) private var dismiss
    private let sessionTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var currentQuestion: AlgTrainerQuestion?
    @State private var selectedAnswerID: String?
    @State private var lastQuestionSeedID: String?
    @State private var isShowingSummary = false
    @State private var answeredCount = 0
    @State private var correctCount = 0
    @State private var currentStreak = 0
    @State private var bestStreak = 0
    @State private var skipCount = 0
    @State private var sessionStartDate = Date()
    @State private var questionStartDate = Date()
    @State private var totalAnsweredRecognitionDuration: TimeInterval = 0
    @State private var now = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scopeTitle)
                        .font(.system(size: 34, weight: .bold))

                    Text(promptText)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.top, 8)
                }
                .padding(.top, 8)

                trainerStatsRow
                trainerSessionTimeCard

                NavigationLink {
                    AlgTrainerWeakReviewView(items: weakItems, languageCode: languageCode)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                        Text(localizedAlgString(key: "algs.trainer.review_weak", languageCode: languageCode))
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.secondary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)

                if let currentQuestion {
                    trainerCaseImage(for: currentQuestion.algCase)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(16)
                        .frame(height: 190)
                        .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(.secondary.opacity(0.08))
                        )
                        .animation(.easeInOut(duration: 0.2), value: currentQuestion.id)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(currentQuestion.choices) { choice in
                            Button {
                                guard selectedAnswerID == nil else { return }
                                let isCorrect = choice.id == currentQuestion.correctAnswerID
                                if let responseDuration = currentRecognitionDuration {
                                    totalAnsweredRecognitionDuration += responseDuration
                                }
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                    selectedAnswerID = choice.id
                                }
                                triggerAnswerHaptic(isCorrect: isCorrect)
                                updateSessionStats(isCorrect: isCorrect, wasSkipped: false)
                                recordAttempt(
                                    answerID: choice.id,
                                    isCorrect: isCorrect,
                                    isSkipped: false,
                                    for: currentQuestion
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    Text(choice.title)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(choiceForegroundStyle(for: choice))
                                        .multilineTextAlignment(.leading)

                                    Spacer()

                                    if let selectedAnswerID, selectedAnswerID == choice.id {
                                        Image(systemName: selectedAnswerID == currentQuestion.correctAnswerID ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(selectedAnswerID == currentQuestion.correctAnswerID ? .green : .red)
                                    } else if selectedAnswerID != nil, choice.id == currentQuestion.correctAnswerID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(choiceBackgroundColor(for: choice))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: selectedAnswerID)

                    if selectedAnswerID == nil {
                        Button {
                            triggerActionHaptic()
                            updateSessionStats(isCorrect: false, wasSkipped: true)
                            recordAttempt(answerID: nil, isCorrect: false, isSkipped: true, for: currentQuestion)
                            withAnimation(.easeInOut(duration: 0.22)) {
                                generateNextQuestion()
                            }
                        } label: {
                            Text(localizedAlgString(key: "algs.trainer.skip", languageCode: languageCode))
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(.secondary.opacity(0.08))
                                )
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if let selectedAnswerID {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(
                                selectedAnswerID == currentQuestion.correctAnswerID
                                    ? localizedAlgString(key: "algs.trainer.correct", languageCode: languageCode)
                                    : localizedAlgString(key: "algs.trainer.incorrect", languageCode: languageCode)
                            )
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(selectedAnswerID == currentQuestion.correctAnswerID ? .green : .red)

                            if selectedAnswerID != currentQuestion.correctAnswerID {
                                Text(
                                    String(
                                        format: localizedAlgString(key: "algs.trainer.correct_answer_format", languageCode: languageCode),
                                        currentQuestion.correctAnswerTitle
                                    )
                                )
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                            }

                            Button {
                                triggerActionHaptic()
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    generateNextQuestion()
                                }
                            } label: {
                                Text(localizedAlgString(key: "algs.trainer.next_question", languageCode: languageCode))
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color.orange)
                                    )
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localizedAlgString(key: "algs.trainer.no_questions_title", languageCode: languageCode))
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(localizedAlgString(key: "algs.trainer.no_questions_body", languageCode: languageCode))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.secondary.opacity(0.08))
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isShowingSummary) {
            CompatibleNavigationContainer {
                AlgTrainerSummaryView(
                    summary: AlgTrainerSessionSummary(
                        title: title,
                        scopeTitle: scopeTitle,
                        languageCode: languageCode,
                        answeredCount: answeredCount,
                        correctCount: correctCount,
                        wrongCount: max(answeredCount - correctCount, 0),
                        skipCount: skipCount,
                        bestStreak: bestStreak,
                        sessionDuration: sessionDuration,
                        averageRecognitionDuration: averageRecognitionDuration
                    ),
                    weakItems: makeAlgTrainerWeakReviewItems(from: decodeAlgTrainerAttempts(from: attemptStore), languageCode: languageCode),
                    onTrainAgain: {
                        isShowingSummary = false
                        resetSession()
                        generateNextQuestion()
                    },
                    onDone: {
                        isShowingSummary = false
                        dismiss()
                    }
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(localizedAlgString(key: "algs.trainer.end", languageCode: languageCode)) {
                    if answeredCount == 0 && skipCount == 0 {
                        dismiss()
                    } else {
                        triggerActionHaptic()
                        isShowingSummary = true
                    }
                }
                .font(.system(size: 15, weight: .semibold))
            }
        }
        .compatibleTabBarHidden()
        .onAppear {
            if currentQuestion == nil {
                sessionStartDate = Date()
                now = sessionStartDate
                generateNextQuestion()
            }
        }
        .onReceive(sessionTicker) { value in
            now = value
        }
    }

    private var promptText: String {
        switch level {
        case .group:
            return localizedAlgString(key: "algs.trainer.prompt_group", languageCode: languageCode)
        case .subset:
            return localizedAlgString(key: "algs.trainer.prompt_subset", languageCode: languageCode)
        case .caseName:
            return localizedAlgString(key: "algs.trainer.prompt_case", languageCode: languageCode)
        }
    }

    private var accuracyText: String {
        guard answeredCount > 0 else {
            return localizedAlgString(key: "algs.trainer.accuracy_empty", languageCode: languageCode)
        }

        let percent = Int((Double(correctCount) / Double(answeredCount) * 100).rounded())
        return String(
            format: localizedAlgString(key: "algs.trainer.accuracy_format", languageCode: languageCode),
            percent,
            correctCount,
            answeredCount
        )
    }

    private var trainerStatsRow: some View {
        HStack(spacing: 12) {
            trainerStatCard(
                title: localizedAlgString(key: "algs.trainer.score_title", languageCode: languageCode),
                value: accuracyText
            )

            trainerStatCard(
                title: localizedAlgString(key: "algs.trainer.streak_title", languageCode: languageCode),
                value: String(currentStreak)
            )

            trainerStatCard(
                title: localizedAlgString(key: "algs.trainer.best_streak_title", languageCode: languageCode),
                value: String(bestStreak)
            )
        }
    }

    private var trainerSessionTimeCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .semibold))
            Text(localizedAlgString(key: "algs.trainer.session_time_title", languageCode: languageCode))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatAlgTrainerSessionDuration(sessionDuration))
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    private var weakItems: [AlgTrainerWeakReviewItem] {
        makeAlgTrainerWeakReviewItems(from: decodeAlgTrainerAttempts(from: attemptStore), languageCode: languageCode)
    }

    private var sessionDuration: TimeInterval {
        max(now.timeIntervalSince(sessionStartDate), 0)
    }

    private var currentRecognitionDuration: TimeInterval? {
        guard selectedAnswerID == nil else { return nil }
        return max(Date().timeIntervalSince(questionStartDate), 0)
    }

    private var averageRecognitionDuration: TimeInterval? {
        guard answeredCount > 0 else { return nil }
        return totalAnsweredRecognitionDuration / Double(answeredCount)
    }

    private func generateNextQuestion() {
        guard !seeds.isEmpty else {
            currentQuestion = nil
            selectedAnswerID = nil
            return
        }

        let answerPool = seeds.reduce(into: [String: String]()) { partialResult, seed in
            partialResult[seed.answerID] = seed.answerTitle
        }
        let candidateSeeds: [AlgTrainerQuestionSeed]
        if let lastQuestionSeedID, seeds.count > 1 {
            let filtered = seeds.filter { $0.id != lastQuestionSeedID }
            candidateSeeds = filtered.isEmpty ? seeds : filtered
        } else {
            candidateSeeds = seeds
        }

        guard let seed = candidateSeeds.randomElement() else {
            currentQuestion = nil
            selectedAnswerID = nil
            return
        }

        let distractorIDs = Array(answerPool.keys.filter { $0 != seed.answerID }).shuffled().prefix(3)
        let choiceIDs = ([seed.answerID] + distractorIDs).shuffled()
        let choices = choiceIDs.map { choiceID in
            AlgTrainerQuestionChoice(id: choiceID, title: answerPool[choiceID] ?? choiceID)
        }

        currentQuestion = AlgTrainerQuestion(
            id: UUID().uuidString,
            algCase: seed.algCase,
            choices: choices,
            correctAnswerID: seed.answerID,
            correctAnswerTitle: seed.answerTitle
        )
        lastQuestionSeedID = seed.id
        selectedAnswerID = nil
        questionStartDate = Date()
    }

    private func updateSessionStats(isCorrect: Bool, wasSkipped: Bool) {
        if !wasSkipped {
            answeredCount += 1
        }

        if isCorrect {
            correctCount += 1
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
        } else {
            if wasSkipped {
                skipCount += 1
            }
            currentStreak = 0
        }
    }

    private func resetSession() {
        currentQuestion = nil
        selectedAnswerID = nil
        lastQuestionSeedID = nil
        answeredCount = 0
        correctCount = 0
        currentStreak = 0
        bestStreak = 0
        skipCount = 0
        totalAnsweredRecognitionDuration = 0
        sessionStartDate = Date()
        now = sessionStartDate
        questionStartDate = sessionStartDate
    }

    @ViewBuilder
    private func trainerCaseImage(for algCase: AlgCase) -> some View {
        #if os(iOS)
        if let image = AlgCaseImageProvider.image(named: algCase.imageKey) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        } else {
            fallbackTrainerCaseImage(for: algCase)
        }
        #else
        fallbackTrainerCaseImage(for: algCase)
        #endif
    }

    private func fallbackTrainerCaseImage(for algCase: AlgCase) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.blue.opacity(0.12))

            Text(localizedAlgCaseName(setID: setID, caseName: algCase.displayName, languageCode: languageCode))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.blue)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .padding(.horizontal, 12)
        }
    }

    private func choiceBackgroundColor(for choice: AlgTrainerQuestionChoice) -> Color {
        guard let currentQuestion else { return Color.secondary.opacity(0.08) }
        guard let selectedAnswerID else { return Color.secondary.opacity(0.08) }

        if choice.id == currentQuestion.correctAnswerID {
            return Color.green.opacity(0.14)
        }

        if choice.id == selectedAnswerID {
            return Color.red.opacity(0.12)
        }

        return Color.secondary.opacity(0.08)
    }

    private func choiceForegroundStyle(for choice: AlgTrainerQuestionChoice) -> Color {
        guard let currentQuestion else { return .primary }
        guard let selectedAnswerID else { return .primary }

        if choice.id == currentQuestion.correctAnswerID {
            return .green
        }

        if choice.id == selectedAnswerID {
            return .red
        }

        return .primary
    }

    private func trainerStatCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    private func triggerAnswerHaptic(isCorrect: Bool) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(isCorrect ? .success : .error)
        #endif
    }

    private func triggerActionHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    private func recordAttempt(answerID: String?, isCorrect: Bool, isSkipped: Bool, for question: AlgTrainerQuestion) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var records = (try? decoder.decode([AlgTrainerAttemptRecord].self, from: Data(attemptStore.utf8))) ?? []
        records.append(
            AlgTrainerAttemptRecord(
                id: UUID().uuidString,
                setID: setID,
                scopeID: scopeID,
                level: level,
                caseID: question.algCase.id,
                answerID: answerID,
                isCorrect: isCorrect,
                isSkipped: isSkipped,
                timestamp: Date()
            )
        )
        if records.count > 500 {
            records = Array(records.suffix(500))
        }
        if let data = try? encoder.encode(records),
           let string = String(data: data, encoding: .utf8) {
            attemptStore = string
        }
    }
}

struct AlgTrainerHomeView: View {
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("algBrowseOrganizationStore") private var browseOrganizationStore: String = "{}"
    @AppStorage("algTrainerAttemptStore") private var trainerAttemptStore: String = "[]"
    @AppStorage("algDismissedRecentPracticeRecordID") private var dismissedRecentPracticeRecordID: String = ""

    private var trainerSections: [(AlgSectionData, [AlgTrainerSetOption])] {
        makeAlgTrainerSetOptions(languageCode: appLanguage)
    }

    private var weakPracticeItems: [AlgTrainerWeakReviewItem] {
        makeAlgTrainerWeakReviewItems(
            from: decodeAlgTrainerAttempts(from: trainerAttemptStore),
            languageCode: appLanguage
        )
    }

    private var recentPracticeContext: AlgRecentPracticeContext? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let records = try? decoder.decode([AlgTrainerAttemptRecord].self, from: Data(trainerAttemptStore.utf8)),
              let latestRecord = records.sorted(by: { $0.timestamp > $1.timestamp }).first,
              let set = AlgLibrarySet(itemID: latestRecord.setID),
              let payload = AlgLibraryLoader.load(set) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = appLocale(for: appLanguage)
        formatter.dateFormat = appLocalizedString("algs.trainer.last_practiced_format", languageCode: appLanguage)

        let lastPracticedText = String(
            format: localizedAlgString(key: "algs.trainer.continue_subtitle_format", languageCode: appLanguage),
            formatter.string(from: latestRecord.timestamp)
        )

        if latestRecord.scopeID == latestRecord.setID {
            let title = AlgSectionData.allSections
                .flatMap(\.items)
                .first { $0.id.caseInsensitiveCompare(payload.set) == .orderedSame }
                .map { appLocalizedString("algs.item.\($0.id).title", languageCode: appLanguage, defaultValue: payload.set) } ?? payload.set

            return AlgRecentPracticeContext(
                id: latestRecord.scopeID,
                dismissToken: latestRecord.id,
                title: title,
                subtitle: lastPracticedText,
                destination: .set(payload)
            )
        }

        if let subset = orderedSubsets(from: payload.cases).first(where: { "\(payload.set)_\($0.id)" == latestRecord.scopeID }) {
            return AlgRecentPracticeContext(
                id: latestRecord.scopeID,
                dismissToken: latestRecord.id,
                title: localizedAlgSubgroup(subset.title, languageCode: appLanguage),
                subtitle: lastPracticedText,
                destination: .subset(payload, subset)
            )
        }

        return nil
    }

    var body: some View {
        List {
            headerSection

            if let recentPracticeContext,
               recentPracticeContext.dismissToken != dismissedRecentPracticeRecordID {
                Section {
                    HStack(spacing: 12) {
                        NavigationLink {
                            recentPracticeTrainerDestination(for: recentPracticeContext)
                        } label: {
                            recentPracticeLabel(recentPracticeContext)
                        }

                        Button {
                            dismissedRecentPracticeRecordID = recentPracticeContext.dismissToken
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(.secondary.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !weakPracticeItems.isEmpty {
                Section {
                    NavigationLink {
                        AlgTrainerWeakReviewView(items: weakPracticeItems, languageCode: appLanguage)
                    } label: {
                        weakPracticeLabel
                    }
                }
            }

            ForEach(trainerSections, id: \.0.id) { section, options in
                Section {
                    ForEach(options) { option in
                        NavigationLink {
                            trainerDestination(for: option.payload)
                        } label: {
                            trainerSetRow(option)
                        }
                    }
                } header: {
                    Text(section.localizedTitleKey)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(localizedAlgString(key: "algs.trainer.title", languageCode: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(localizedAlgString(key: "algs.trainer.title", languageCode: appLanguage))
                    .font(.system(size: 34, weight: .bold))

                Text(localizedAlgString(key: "algs.trainer.home_subtitle", languageCode: appLanguage))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)

                Divider()
                    .padding(.top, 8)
            }
            .padding(.vertical, 4)
        }
        .listRowSeparator(.hidden)
    }

    private func recentPracticeLabel(_ context: AlgRecentPracticeContext) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedAlgString(key: "algs.trainer.continue_title", languageCode: appLanguage))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(context.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(context.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var weakPracticeLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedAlgString(key: "algs.trainer.weak_title", languageCode: appLanguage))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(
                    String(
                        format: localizedAlgString(key: "algs.trainer.weak_count_format", languageCode: appLanguage),
                        weakPracticeItems.count
                    )
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func trainerSetRow(_ option: AlgTrainerSetOption) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(option.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(option.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func trainerDestination(for payload: AlgSetPayload) -> some View {
        let organization = algBrowseOrganization(setID: payload.set, storage: browseOrganizationStore)
        let config = makeSetTrainerSeeds(payload: payload, languageCode: appLanguage, organization: organization)
        return AlgRecognitionTrainerView(
            title: localizedAlgString(key: "algs.trainer.train_set", languageCode: appLanguage),
            scopeTitle: payload.set,
            languageCode: appLanguage,
            setID: payload.set,
            scopeID: payload.set,
            level: config.0,
            seeds: config.1
        )
    }

    @ViewBuilder
    private func recentPracticeTrainerDestination(for context: AlgRecentPracticeContext) -> some View {
        switch context.destination {
        case .set(let payload):
            trainerDestination(for: payload)
        case .subset(let payload, let subset):
            let config = makeSubsetTrainerSeeds(setID: payload.set, subset: subset, languageCode: appLanguage)
            AlgRecognitionTrainerView(
                title: localizedAlgString(key: "algs.trainer.train_subset", languageCode: appLanguage),
                scopeTitle: localizedAlgSubgroup(subset.title, languageCode: appLanguage),
                languageCode: appLanguage,
                setID: payload.set,
                scopeID: "\(payload.set)_\(subset.id)",
                level: config.0,
                seeds: config.1
            )
        }
    }
}

struct AlgTrainerWeakReviewView: View {
    let items: [AlgTrainerWeakReviewItem]
    let languageCode: String

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedAlgString(key: "algs.trainer.weak_title", languageCode: languageCode))
                        .font(.system(size: 34, weight: .bold))

                    Text(localizedAlgString(key: "algs.trainer.weak_subtitle", languageCode: languageCode))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.top, 8)
                }
                .padding(.vertical, 4)
            }
            .listRowSeparator(.hidden)

            if items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizedAlgString(key: "algs.trainer.weak_empty_title", languageCode: languageCode))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(localizedAlgString(key: "algs.trainer.weak_empty_body", languageCode: languageCode))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            } else {
                ForEach(items) { item in
                    NavigationLink {
                        AlgCaseDetailView(payload: item.payload, algCase: item.algCase)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.caseTitle)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(item.setTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)

                            Text(item.subtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(localizedAlgString(key: "algs.trainer.weak_nav_title", languageCode: languageCode))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AlgSearchView: View {
    let items: [AlgSearchItem]
    let languageCode: String

    @State private var query = ""

    private var filteredItems: [AlgSearchItem] {
        items.filter { $0.matches(query) }
    }

    private var setItems: [AlgSearchItem] {
        filteredItems.filter { $0.kind == .set }
    }

    private var subsetItems: [AlgSearchItem] {
        filteredItems.filter { $0.kind == .subset }
    }

    private var caseItems: [AlgSearchItem] {
        filteredItems.filter { $0.kind == .caseName }
    }

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizedAlgString(key: "algs.search.empty_query_title", languageCode: languageCode))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(localizedAlgString(key: "algs.search.empty_query_body", languageCode: languageCode))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            } else if filteredItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizedAlgString(key: "algs.search.no_results_title", languageCode: languageCode))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(localizedAlgString(key: "algs.search.no_results_body", languageCode: languageCode))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            } else {
                if !setItems.isEmpty {
                    Section(localizedAlgString(key: "algs.search.section_sets", languageCode: languageCode)) {
                        ForEach(setItems) { item in
                            searchRow(item)
                        }
                    }
                }

                if !subsetItems.isEmpty {
                    Section(localizedAlgString(key: "algs.search.section_subsets", languageCode: languageCode)) {
                        ForEach(subsetItems) { item in
                            searchRow(item)
                        }
                    }
                }

                if !caseItems.isEmpty {
                    Section(localizedAlgString(key: "algs.search.section_cases", languageCode: languageCode)) {
                        ForEach(caseItems) { item in
                            searchRow(item)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(localizedAlgString(key: "algs.search.title", languageCode: languageCode))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(localizedAlgString(key: "algs.search.placeholder", languageCode: languageCode))
        )
    }

    @ViewBuilder
    private func searchRow(_ item: AlgSearchItem) -> some View {
        NavigationLink {
            destinationView(for: item)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(item.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func destinationView(for item: AlgSearchItem) -> some View {
        switch item.destination {
        case .set(let payload):
            AlgCaseListView(payload: payload)
        case .subset(let payload, let subset):
            AlgSubsetCaseListView(payload: payload, subset: subset)
        case .caseDetail(let payload, let algCase):
            AlgCaseDetailView(payload: payload, algCase: algCase)
        case .placeholder(let item):
            AlgSetPlaceholderView(item: item)
        }
    }
}

struct AlgTrainerSummaryView: View {
    let summary: AlgTrainerSessionSummary
    let weakItems: [AlgTrainerWeakReviewItem]
    let onTrainAgain: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedAlgString(key: "algs.trainer.summary_title", languageCode: summary.languageCode))
                        .font(.system(size: 34, weight: .bold))

                    Text(summary.scopeTitle)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.top, 8)
                }
                .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    summaryStatCard(
                        title: localizedAlgString(key: "algs.trainer.score_title", languageCode: summary.languageCode),
                        value: accuracyText
                    )
                    summaryStatCard(
                        title: localizedAlgString(key: "algs.trainer.session_time_title", languageCode: summary.languageCode),
                        value: formatAlgTrainerSessionDuration(summary.sessionDuration)
                    )
                    summaryStatCard(
                        title: localizedAlgString(key: "algs.trainer.answered_title", languageCode: summary.languageCode),
                        value: String(summary.answeredCount)
                    )
                    summaryStatCard(
                        title: localizedAlgString(key: "algs.trainer.average_time_title", languageCode: summary.languageCode),
                        value: averageRecognitionText
                    )
                    summaryStatCard(
                        title: localizedAlgString(key: "algs.trainer.best_streak_title", languageCode: summary.languageCode),
                        value: String(summary.bestStreak)
                    )
                    summaryStatCard(
                        title: localizedAlgString(key: "algs.trainer.wrong_title", languageCode: summary.languageCode),
                        value: String(summary.wrongCount)
                    )
                    summaryStatCard(
                        title: localizedAlgString(key: "algs.trainer.skipped_title", languageCode: summary.languageCode),
                        value: String(summary.skipCount)
                    )
                }

                VStack(spacing: 12) {
                    Button(action: onTrainAgain) {
                        Text(localizedAlgString(key: "algs.trainer.train_again", languageCode: summary.languageCode))
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.orange)
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    if !weakItems.isEmpty {
                        NavigationLink {
                            AlgTrainerWeakReviewView(items: weakItems, languageCode: summary.languageCode)
                        } label: {
                            Text(localizedAlgString(key: "algs.trainer.review_weak", languageCode: summary.languageCode))
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(.secondary.opacity(0.08))
                                )
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onDone) {
                        Text(localizedAlgString(key: "algs.trainer.done", languageCode: summary.languageCode))
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.secondary.opacity(0.08))
                            )
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle(summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .compatibleTabBarHidden()
    }

    private var accuracyText: String {
        guard summary.answeredCount > 0 else {
            return localizedAlgString(key: "algs.trainer.accuracy_empty", languageCode: summary.languageCode)
        }

        let percent = Int((Double(summary.correctCount) / Double(summary.answeredCount) * 100).rounded())
        return String(
            format: localizedAlgString(key: "algs.trainer.accuracy_format", languageCode: summary.languageCode),
            percent,
            summary.correctCount,
            summary.answeredCount
        )
    }

    private var averageRecognitionText: String {
        guard let average = summary.averageRecognitionDuration else {
            return localizedAlgString(key: "algs.trainer.accuracy_empty", languageCode: summary.languageCode)
        }

        return formatAlgTrainerAverageDuration(average, languageCode: summary.languageCode)
    }

    private func summaryStatCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }
}
