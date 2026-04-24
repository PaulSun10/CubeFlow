import SwiftUI

struct StreakButton: View {
    let isTodaySolved: Bool
    let streakCount: Int
    let longestStreak: Int
    let solvedDayCounts: [Date: Int]
    let fireRedImageName: String
    let fireGrayImageName: String

    @State private var showingSheet = false

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(isTodaySolved ? fireRedImageName : fireGrayImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .scaleEffect(isTodaySolved ? 1.05 : 0.95)
                    .opacity(isTodaySolved ? 1.0 : 0.7)
                    .animation(.snappy(duration: 0.2, extraBounce: 0), value: isTodaySolved)

                if streakCount >= 1 {
                    Text("\(streakCount)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .compatibleGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSheet) {
            StreakDetailSheet(
                isTodaySolved: isTodaySolved,
                streakCount: streakCount,
                longestStreak: longestStreak,
                solvedDayCounts: solvedDayCounts
            )
            .compatibleLargeSheet()
        }
    }
}

private struct StreakDetailSheet: View {
    let isTodaySolved: Bool
    let streakCount: Int
    let longestStreak: Int
    let solvedDayCounts: [Date: Int]
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    var body: some View {
        navigationContent
    }

    @ViewBuilder
    private var navigationContent: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                content
            }
        } else {
            NavigationView {
                content
            }
            .navigationViewStyle(.stack)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(isTodaySolved ? "streak_fire_red" : "streak_fire_gray")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .scaleEffect(streakCount > 0 ? 1.05 : 1.0)
                            .animation(.snappy(duration: 0.25, extraBounce: 0.2), value: streakCount)
                        Text(streakDaysText)
                            .font(.system(size: 32, weight: .semibold))
                            .compatibleNumericTextTransition()
                    }
                    .animation(.snappy(duration: 0.25, extraBounce: 0.1), value: streakCount)

                    Text(streakSubtitleKey)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    Text(bestStreakText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                StreakCalendarView(
                    solvedDayCounts: solvedDayCounts
                )
                .frame(height: 590)
                .padding(.top, -100)

                if !isTodaySolved {
                    Text("streak.tip")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .navigationTitle(Text("streak.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
    }

    private var streakSubtitleKey: LocalizedStringKey {
        if streakCount == 0 {
            return "streak.subtitle.start"
        }
        if isTodaySolved {
            return "streak.subtitle.fire"
        }
        return "streak.subtitle.keep"
    }

    private var bestStreakText: String {
        String(
            format: appLocalizedString("streak.best_with_unit_format", languageCode: appLanguage),
            longestStreak,
            dayUnit(for: longestStreak)
        )
    }

    private var streakDaysText: String {
        "\(streakCount) \(dayUnit(for: streakCount))"
    }

    private func dayUnit(for count: Int) -> String {
        let key = count >= 2 ? "streak.day.plural" : "streak.day.singular"
        return appLocalizedString(key, languageCode: appLanguage)
    }
}

private struct StreakCalendarView: View {
    let solvedDayCounts: [Date: Int]

    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var selectedDate = Date()
    @State private var displayedMonth = Date()
    @State private var showBubble = false
    @State private var bubbleToken = UUID()
    @State private var bubbleDate: Date?
    @State private var bubbleAnchor: CGPoint = .zero

    private let cellSize: CGFloat = 46
    private let columns = Array(repeating: GridItem(.fixed(46), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthTitle(displayedMonth))
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Button {
                    displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdaySymbols(), id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                ForEach(monthGridDates(), id: \.self) { date in
                    if let date {
                        dayCell(for: date)
                    } else {
                        Color.clear
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
        .coordinateSpace(name: "calendar")
        .overlay(alignment: .topLeading) {
            if showBubble, let bubbleDate {
                let dayStart = Calendar.current.startOfDay(for: bubbleDate)
                let solveCount = solvedDayCounts[dayStart] ?? 0
                bubbleView(for: dayStart, solveCount: solveCount)
                    .position(x: bubbleAnchor.x, y: bubbleAnchor.y - 8)
                    .transition(.opacity.combined(with: .scale))
                    .id(bubbleToken)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: bubbleToken)
            }
        }
        .onAppear {
            displayedMonth = startOfMonth(Date())
        }
        .onChange(of: bubbleDate) { _ in
            showBubble = true
        }
    }

    private func dayCell(for date: Date) -> some View {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let solveCount = solvedDayCounts[startOfDay] ?? 0
        let isSolved = solveCount > 0
        let isToday = calendar.isDateInToday(date)
        let circleSize: CGFloat = 40

        return ZStack {
            if isSolved {
                Circle()
                    .frame(width: circleSize, height: circleSize)
                    .compatibleTintedGlass(Color(red: 1.0, green: 0.522, blue: 0.0), in: Circle())
                    .environment(\.colorScheme, .light)
            }

            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(width: cellSize, height: cellSize)
        .overlay(
            Circle()
                .stroke(isToday ? Color.orange : Color.clear, lineWidth: 1.5)
                .frame(width: circleSize, height: circleSize)
        )
        .contentShape(Rectangle())
        .overlay {
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedDate = date
                        bubbleDate = startOfDay
                        bubbleAnchor = CGPoint(x: proxy.frame(in: .named("calendar")).midX, y: proxy.frame(in: .named("calendar")).minY)
                        bubbleToken = UUID()
                        showBubble = true
                    }
            }
        }
    }

    private func bubbleView(for date: Date, solveCount: Int) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(dateLine(for: date, languageCode: appLanguage))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: true, vertical: false)
            Text(solveLine(for: solveCount))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .compatibleGlass(in: SpeechBubbleShape(cornerRadius: 14, tailWidth: 14, tailHeight: 8))
        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
    }

    private func monthGridDates() -> [Date?] {
        let calendar = Calendar.current
        let start = startOfMonth(displayedMonth)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }

        let weekday = calendar.component(.weekday, from: start)
        let leadingEmpty = (weekday - calendar.firstWeekday + 7) % 7

        var dates: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: start) {
                dates.append(date)
            }
        }

        let remainder = dates.count % 7
        if remainder != 0 {
            dates.append(contentsOf: Array(repeating: nil, count: 7 - remainder))
        }
        return dates
    }

    private func startOfMonth(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLocale(for: appLanguage)
        formatter.dateFormat = appLocalizedString("streak.month_title_format", languageCode: appLanguage)
        return formatter.string(from: date)
    }

    private func weekdaySymbols() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = .current
        let symbols = formatter.shortWeekdaySymbols ?? Calendar.current.shortWeekdaySymbols
        let firstIndex = Calendar.current.firstWeekday - 1
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    private func solveLine(for count: Int) -> String {
        let key = count == 1 ? "streak.solve.singular_format" : "streak.solve.plural_format"
        return String(format: appLocalizedString(key, languageCode: appLanguage), count)
    }
}

private func dateLine(for date: Date, languageCode: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = appLocale(for: languageCode)
    formatter.dateFormat = appLocalizedString("streak.date_line_format", languageCode: languageCode)
    return formatter.string(from: date)
}

private struct SpeechBubbleShape: Shape {
    var cornerRadius: CGFloat = 14
    var tailWidth: CGFloat = 14
    var tailHeight: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bubbleRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height - tailHeight
        )

        path.addRoundedRect(in: bubbleRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        let midX = bubbleRect.midX
        let tailHalf = tailWidth / 2
        let tailStart = CGPoint(x: midX - tailHalf, y: bubbleRect.maxY)
        let tailTip = CGPoint(x: midX, y: bubbleRect.maxY + tailHeight)
        let tailEnd = CGPoint(x: midX + tailHalf, y: bubbleRect.maxY)

        path.move(to: tailStart)
        path.addLine(to: tailTip)
        path.addLine(to: tailEnd)
        path.closeSubpath()
        return path
    }
}
