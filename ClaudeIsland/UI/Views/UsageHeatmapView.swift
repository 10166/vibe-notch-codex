//
//  UsageHeatmapView.swift
//  ClaudeIsland
//
//  Compact local usage heatmap for Claude Code and Codex CLI sessions.
//

import SwiftUI

struct UsageHeatmapView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var store = UsageAnalyticsStore.shared

    @State private var metric: UsageAnalyticsMetric = .tokens
    @State private var agentFilter: UsageAnalyticsAgentFilter = .all
    @State private var range: UsageAnalyticsRange = .twelveWeeks
    @State private var selectedDateKey: String = UsageHeatmapView.todayKey()
    @State private var hoveredCell: UsageHeatmapHover?

    private let maxCellSize: CGFloat = 11
    private let minCellSize: CGFloat = 5
    private let cellSpacing: CGFloat = 3
    private let heatmapPadding: CGFloat = 8
    private let monthLabelHeight: CGFloat = 12
    private let weekdayLabelWidth: CGFloat = 28
    private let heatmapLabelSpacing: CGFloat = 6
    private let monthGridSpacing: CGFloat = 4
    private let hoverTooltipWidth: CGFloat = 112
    private let hoverTooltipHeight: CGFloat = 28

    var body: some View {
        let presentation = makePresentation()
        VStack(alignment: .leading, spacing: 10) {
            header
            controls
            summaryStrip(presentation)
            heatmap(presentation)
            dayDetail(presentation)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            selectedDateKey = Self.todayKey()
            store.start(range: range)
        }
        .onDisappear {
            store.stop()
        }
        .onChange(of: range) { _, newRange in
            hoveredCell = nil
            store.refresh(range: newRange)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.showMenu()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)

            Text("Usage")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .scaleEffect(0.45)
                    .frame(width: 16, height: 16)
            }

            Button {
                store.refresh(range: range)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            controlGroup("Metric") {
                Picker(selection: $metric) {
                    ForEach(UsageAnalyticsMetric.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .frame(width: 216)
            }

            HStack(spacing: 12) {
                controlGroup("Agent") {
                    Picker(selection: $agentFilter) {
                        ForEach(UsageAnalyticsAgentFilter.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 174)
                }

                controlGroup("Range") {
                    Picker(selection: $range) {
                        ForEach(UsageAnalyticsRange.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 122)
                }
            }
        }
        .controlSize(.small)
        .tint(Color.white.opacity(0.25))
    }

    private func controlGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.82))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 48, alignment: .leading)

            content()
                .labelsHidden()
        }
    }

    private func summaryStrip(_ presentation: UsageHeatmapPresentation) -> some View {
        HStack(spacing: 8) {
            SummaryPill(label: "Tokens", value: UsageFormatters.compactTokens(presentation.totalTokens), accent: TerminalColors.green)
            SummaryPill(label: "Cost", value: UsageFormatters.cost(presentation.totalCostMicros), accent: TerminalColors.amber)
            SummaryPill(label: "Sessions", value: "\(presentation.totalSessions)", accent: TerminalColors.blue)
        }
    }

    private func heatmap(_ presentation: UsageHeatmapPresentation) -> some View {
        GeometryReader { proxy in
            let weeks = presentation.weekColumns
            let weekCount = max(weeks.count, 1)
            let availableWidth = max(0, proxy.size.width - heatmapPadding * 2 - weekdayLabelWidth - heatmapLabelSpacing)
            let cellSize = heatmapCellSize(weekCount: weekCount, availableWidth: availableWidth)
            let gridWidth = heatmapGridWidth(weekCount: weekCount, cellSize: cellSize)
            let gridHeight = heatmapGridHeight(cellSize: cellSize)

            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: monthGridSpacing) {
                    HStack(spacing: heatmapLabelSpacing) {
                        Color.clear
                            .frame(width: weekdayLabelWidth, height: monthLabelHeight)

                        monthLabels(presentation.monthLabels, cellSize: cellSize, gridWidth: gridWidth)
                    }

                    HStack(alignment: .top, spacing: heatmapLabelSpacing) {
                        weekdayLabels(cellSize: cellSize)

                        HStack(alignment: .top, spacing: cellSpacing) {
                            ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, days in
                                UsageHeatmapWeekColumn(
                                    weekIndex: weekIndex,
                                    days: days,
                                    metric: metric,
                                    maxValue: presentation.maxMetricValue,
                                    selectedDateKey: $selectedDateKey,
                                    hoveredCell: $hoveredCell,
                                    cellSize: cellSize,
                                    cellSpacing: cellSpacing
                                )
                            }
                        }
                        .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
                    }
                }

                if let hoveredCell {
                    UsageHeatmapHoverTooltip(day: hoveredCell.day)
                        .frame(width: hoverTooltipWidth, height: hoverTooltipHeight)
                        .offset(
                            x: hoverTooltipX(hoveredCell.weekIndex, cellSize: cellSize, gridWidth: gridWidth),
                            y: hoverTooltipY(hoveredCell.dayIndex, cellSize: cellSize)
                        )
                        .allowsHitTesting(false)
                }
            }
            .frame(width: weekdayLabelWidth + heatmapLabelSpacing + gridWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(heatmapPadding)
        }
        .frame(height: heatmapHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.035))
        )
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func monthLabels(_ labels: [UsageHeatmapMonthLabel], cellSize: CGFloat, gridWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(labels) { label in
                Text(label.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.34))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: CGFloat(label.weekIndex) * (cellSize + cellSpacing))
            }
        }
        .frame(width: gridWidth, height: monthLabelHeight, alignment: .topLeading)
        .clipped()
    }

    private func weekdayLabels(cellSize: CGFloat) -> some View {
        let labels = ["", "Mon", "", "Wed", "", "Fri", ""]
        return VStack(spacing: cellSpacing) {
            ForEach(labels.indices, id: \.self) { index in
                Text(labels[index])
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.28))
                    .lineLimit(1)
                    .frame(width: weekdayLabelWidth, height: cellSize, alignment: .trailing)
            }
        }
    }

    private func dayDetail(_ presentation: UsageHeatmapPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedDateTitle(presentation.selectedDateKey))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))

                Spacer()

                Text(UsageFormatters.metricValue(presentation.selectedBucket.value(for: metric), metric: metric))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(metricAccent)
            }

            if presentation.selectedSessions.isEmpty {
                Text(store.snapshot.sessions.isEmpty ? "No usage data yet" : "No sessions on this day")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, minHeight: 86, alignment: .center)
            } else {
                projectBreakdown(presentation)
                sessionList(presentation)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func projectBreakdown(_ presentation: UsageHeatmapPresentation) -> some View {
        HStack(spacing: 6) {
            ForEach(presentation.topProjects, id: \.name) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)

                    Text(UsageFormatters.compactTokens(item.tokens))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.38))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.045))
                )
            }
        }
    }

    private func sessionList(_ presentation: UsageHeatmapPresentation) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 3) {
                ForEach(presentation.selectedSessions.prefix(8)) { session in
                    UsageSessionRow(session: session)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var heatmapHeight: CGFloat {
        monthLabelHeight + monthGridSpacing + heatmapGridHeight(cellSize: maxCellSize) + heatmapPadding * 2
    }

    private func heatmapCellSize(weekCount: Int, availableWidth: CGFloat) -> CGFloat {
        let totalSpacing = CGFloat(max(weekCount - 1, 0)) * cellSpacing
        let fittedSize = (availableWidth - totalSpacing) / CGFloat(max(weekCount, 1))
        return min(maxCellSize, max(minCellSize, fittedSize))
    }

    private func heatmapGridWidth(weekCount: Int, cellSize: CGFloat) -> CGFloat {
        CGFloat(weekCount) * cellSize + CGFloat(max(weekCount - 1, 0)) * cellSpacing
    }

    private func heatmapGridHeight(cellSize: CGFloat) -> CGFloat {
        cellSize * 7 + cellSpacing * 6
    }

    private func hoverTooltipX(_ weekIndex: Int, cellSize: CGFloat, gridWidth: CGFloat) -> CGFloat {
        let cellX = weekdayLabelWidth + heatmapLabelSpacing + CGFloat(weekIndex) * (cellSize + cellSpacing)
        return min(max(0, cellX - hoverTooltipWidth / 2 + cellSize / 2), max(0, weekdayLabelWidth + heatmapLabelSpacing + gridWidth - hoverTooltipWidth))
    }

    private func hoverTooltipY(_ dayIndex: Int, cellSize: CGFloat) -> CGFloat {
        let cellY = monthLabelHeight + monthGridSpacing + CGFloat(dayIndex) * (cellSize + cellSpacing)
        return max(monthLabelHeight, cellY - hoverTooltipHeight - 6)
    }

    private func makePresentation() -> UsageHeatmapPresentation {
        let filteredSessions = store.snapshot.sessions.filter { agentFilter.includes($0.agent) }
        let dayBuckets = makeDayBuckets(baseDays: store.snapshot.days, filteredSessions: filteredSessions)
        let weekColumns = makeWeekColumns(dayBuckets)
        let selectedSessions = filteredSessions
            .filter { $0.localDate == selectedDateKey }
            .sorted { $0.endedAt > $1.endedAt }
        let topProjects = Dictionary(grouping: selectedSessions, by: \.projectName)
            .map { (name: $0.key, tokens: $0.value.reduce(0) { $0 + $1.totalTokens }) }
            .sorted { $0.tokens > $1.tokens }
            .prefix(3)

        return UsageHeatmapPresentation(
            selectedDateKey: selectedDateKey,
            totalTokens: filteredSessions.reduce(0) { $0 + $1.totalTokens },
            totalCostMicros: totalCostMicros(filteredSessions),
            totalSessions: filteredSessions.count,
            weekColumns: weekColumns,
            monthLabels: makeMonthLabels(weekColumns),
            maxMetricValue: max(dayBuckets.map { $0.value(for: metric) }.max() ?? 0, 1),
            selectedBucket: dayBuckets.first { $0.localDate == selectedDateKey } ?? emptyBucket(for: selectedDateKey),
            selectedSessions: selectedSessions,
            topProjects: Array(topProjects)
        )
    }

    private func makeDayBuckets(baseDays: [UsageDayBucket], filteredSessions: [UsageSessionRecord]) -> [UsageDayBucket] {
        guard agentFilter != .all else { return baseDays }

        var byDate: [String: UsageDayBucket] = Dictionary(uniqueKeysWithValues: baseDays.map {
            ($0.localDate, UsageDayBucket(
                localDate: $0.localDate,
                date: $0.date,
                inputTokens: 0,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                estimatedCostMicros: nil,
                sessionCount: 0
            ))
        })

        for session in filteredSessions {
            guard var bucket = byDate[session.localDate] else { continue }
            bucket.inputTokens += session.tokens.inputTokens
            bucket.outputTokens += session.tokens.outputTokens
            bucket.cacheReadTokens += session.tokens.cacheReadTokens
            bucket.cacheCreationTokens += session.tokens.cacheCreationTokens
            bucket.sessionCount += 1
            if let cost = session.estimatedCostMicros {
                bucket.estimatedCostMicros = (bucket.estimatedCostMicros ?? 0) + cost
            }
            byDate[session.localDate] = bucket
        }

        return baseDays.compactMap { byDate[$0.localDate] }
    }

    private func makeWeekColumns(_ dayBuckets: [UsageDayBucket]) -> [[UsageDayBucket?]] {
        var columns: [[UsageDayBucket?]] = []
        var current: [UsageDayBucket?] = []
        let calendar = Calendar.current

        for day in dayBuckets {
            let weekday = calendar.component(.weekday, from: day.date) - 1
            if current.isEmpty {
                current = Array(repeating: nil, count: weekday)
            }
            current.append(day)
            if current.count == 7 {
                columns.append(current)
                current = []
            }
        }

        if !current.isEmpty {
            current.append(contentsOf: Array(repeating: nil, count: max(0, 7 - current.count)))
            columns.append(current)
        }
        return columns
    }

    private func makeMonthLabels(_ weekColumns: [[UsageDayBucket?]]) -> [UsageHeatmapMonthLabel] {
        var labels: [UsageHeatmapMonthLabel] = []
        var seenMonths: Set<String> = []
        let calendar = Calendar.current

        for (index, days) in weekColumns.enumerated() {
            let visibleDays = days.compactMap { $0 }
            guard !visibleDays.isEmpty else { continue }

            let labelDay: UsageDayBucket?
            if index == 0 {
                labelDay = visibleDays.first
            } else {
                labelDay = visibleDays.first { calendar.component(.day, from: $0.date) == 1 }
            }

            guard let labelDay else { continue }

            let monthKey = UsageHeatmapView.monthKeyFormatter.string(from: labelDay.date)
            guard !seenMonths.contains(monthKey) else { continue }

            seenMonths.insert(monthKey)
            labels.append(UsageHeatmapMonthLabel(
                weekIndex: index,
                title: UsageHeatmapView.monthLabelFormatter.string(from: labelDay.date)
            ))
        }

        return labels
    }

    private func totalCostMicros(_ sessions: [UsageSessionRecord]) -> Int64? {
        let values = sessions.compactMap(\.estimatedCostMicros)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private func emptyBucket(for dateKey: String) -> UsageDayBucket {
        UsageDayBucket(
            localDate: dateKey,
            date: Date(),
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            estimatedCostMicros: nil,
            sessionCount: 0
        )
    }

    private func selectedDateTitle(_ dateKey: String) -> String {
        guard let date = UsageHeatmapView.dateFormatter.date(from: dateKey) else {
            return dateKey
        }
        return UsageHeatmapView.displayDateFormatter.string(from: date)
    }

    private var metricAccent: Color {
        switch metric {
        case .tokens: return TerminalColors.green
        case .cost: return TerminalColors.amber
        case .sessions: return TerminalColors.blue
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private static let monthKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static let monthLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static func todayKey() -> String {
        dateFormatter.string(from: Date())
    }
}

private struct UsageHeatmapPresentation {
    let selectedDateKey: String
    let totalTokens: Int64
    let totalCostMicros: Int64?
    let totalSessions: Int
    let weekColumns: [[UsageDayBucket?]]
    let monthLabels: [UsageHeatmapMonthLabel]
    let maxMetricValue: Double
    let selectedBucket: UsageDayBucket
    let selectedSessions: [UsageSessionRecord]
    let topProjects: [(name: String, tokens: Int64)]
}

private struct UsageHeatmapMonthLabel: Identifiable {
    let weekIndex: Int
    let title: String

    var id: String { "\(weekIndex)-\(title)" }
}

private struct UsageHeatmapHover: Equatable {
    let weekIndex: Int
    let dayIndex: Int
    let day: UsageDayBucket
}

private struct UsageHeatmapWeekColumn: View {
    let weekIndex: Int
    let days: [UsageDayBucket?]
    let metric: UsageAnalyticsMetric
    let maxValue: Double
    @Binding var selectedDateKey: String
    @Binding var hoveredCell: UsageHeatmapHover?
    let cellSize: CGFloat
    let cellSpacing: CGFloat

    var body: some View {
        VStack(spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { dayIndex in
                cell(for: dayIndex)
            }
        }
    }

    @ViewBuilder
    private func cell(for index: Int) -> some View {
        if index < days.count, let day = days[index] {
            UsageHeatmapCell(
                day: day,
                metric: metric,
                maxValue: maxValue,
                isSelected: day.localDate == selectedDateKey
            ) {
                selectedDateKey = day.localDate
            }
            .onHover { hovering in
                hoveredCell = hovering
                    ? UsageHeatmapHover(weekIndex: weekIndex, dayIndex: index, day: day)
                    : nil
            }
            .frame(width: cellSize, height: cellSize)
        } else {
            Color.clear.frame(width: cellSize, height: cellSize)
        }
    }
}

private struct UsageHeatmapHoverTooltip: View {
    let day: UsageDayBucket

    var body: some View {
        Text(tooltipText)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.white.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
    }

    private var tooltipText: String {
        UsageHeatmapHoverTooltip.formatter.string(from: day.date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

private struct UsageHeatmapCell: View {
    let day: UsageDayBucket
    let metric: UsageAnalyticsMetric
    let maxValue: Double
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5)
                        .stroke(isSelected ? Color.white.opacity(0.75) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.2 : 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var fillColor: Color {
        let value = day.value(for: metric)
        guard value > 0 else {
            return Color.white.opacity(0.055)
        }

        let normalized = min(max(value / maxValue, 0), 1)
        let opacity = 0.22 + normalized * 0.7
        switch metric {
        case .tokens:
            return TerminalColors.green.opacity(opacity)
        case .cost:
            return TerminalColors.amber.opacity(opacity)
        case .sessions:
            return TerminalColors.blue.opacity(opacity)
        }
    }

    private var helpText: String {
        "\(day.localDate) · \(UsageFormatters.compactTokens(day.totalTokens)) tokens · \(UsageFormatters.cost(day.estimatedCostMicros)) · \(day.sessionCount) sessions"
    }
}

private struct SummaryPill: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.36))
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(accent.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.045))
        )
    }
}

private struct UsageSessionRow: View {
    let session: UsageSessionRecord

    var body: some View {
        HStack(spacing: 8) {
            AgentLogoIcon(kind: session.agent == .claude ? .claude : .codex, size: 13)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(session.projectName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.78))
                        .lineLimit(1)

                    if session.isSidechain {
                        Text("Sub")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }

                Text(session.model ?? "Unknown model")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.32))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(UsageFormatters.compactTokens(session.totalTokens))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.62))
                Text(UsageFormatters.cost(session.estimatedCostMicros))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.34))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.white.opacity(0.035))
        )
    }
}
