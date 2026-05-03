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
    @State private var hoveredBarDay: ModelBarHover?
    @State private var hoveredModelName: String?
    @State private var chartMode: UsageChartMode = .heatmap

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
    private let controlLabelWidth: CGFloat = 48
    private let primaryControlWidth: CGFloat = 216
    private let rangeControlWidth: CGFloat = 122

    var body: some View {
        let presentation = makePresentation()
        VStack(alignment: .leading, spacing: 10) {
            header
            controls
            summaryStrip(presentation)
            chartContent(presentation)
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
            hoveredBarDay = nil
            store.refresh(range: newRange)
        }
        .onChange(of: chartMode) { _, _ in
            hoveredCell = nil
            hoveredBarDay = nil
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

            Button {
                viewModel.showQuota()
            } label: {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                controlLabel("Metric")
                metricPicker
                    .frame(width: primaryControlWidth)
                Spacer()
                    .frame(width: 14)
                controlLabel("Chart")
                chartModePicker
                    .frame(width: rangeControlWidth)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                controlLabel("Agent")
                agentPicker
                    .frame(width: primaryControlWidth)
                Spacer()
                    .frame(width: 14)
                controlLabel("Range")
                rangePicker
                    .frame(width: rangeControlWidth)
                Spacer(minLength: 0)
            }
        }
        .controlSize(.small)
        .tint(Color.white.opacity(0.25))
    }

    private var metricPicker: some View {
        Picker(selection: $metric) {
            ForEach(UsageAnalyticsMetric.allCases) { item in
                Text(item.displayName).tag(item)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var agentPicker: some View {
        Picker(selection: $agentFilter) {
            ForEach(UsageAnalyticsAgentFilter.allCases) { item in
                Text(item.displayName).tag(item)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var rangePicker: some View {
        Picker(selection: $range) {
            ForEach(UsageAnalyticsRange.allCases) { item in
                Text(item.displayName).tag(item)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var chartModePicker: some View {
        Picker(selection: $chartMode) {
            ForEach(UsageChartMode.allCases) { item in
                Text(item.displayName).tag(item)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private func chartContent(_ presentation: UsageHeatmapPresentation) -> some View {
        switch chartMode {
        case .heatmap:
            heatmap(presentation)
        case .stackedBar:
            modelDistributionBar(presentation)
        case .barChart:
            modelBarChart(presentation)
        }
    }

    private func controlLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.82))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: controlLabelWidth, alignment: .leading)
    }

    private func summaryStrip(_ presentation: UsageHeatmapPresentation) -> some View {
        HStack(spacing: 8) {
            SummaryPill(label: "Tokens", value: UsageFormatters.compactTokens(presentation.totalTokens), accent: TerminalColors.green)
            SummaryPill(label: "Cost", value: UsageFormatters.cost(presentation.totalCostMicros), accent: TerminalColors.amber)
            SummaryPill(label: "Sessions", value: "\(presentation.totalSessions)", accent: TerminalColors.blue)
        }
    }

    @ViewBuilder
    private func modelDistributionBar(_ presentation: UsageHeatmapPresentation) -> some View {
        if presentation.modelTotalValue > 0, !presentation.modelEntries.isEmpty {
            modelDistributionBarContent(presentation)
        }
    }

    private func modelDistributionBarContent(_ presentation: UsageHeatmapPresentation) -> some View {
        let entries = presentation.modelEntries
        let total = presentation.modelTotalValue

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .center) {
                    HStack(spacing: 1.5) {
                        ForEach(entries) { entry in
                            let fraction = entry.value / total
                            RoundedRectangle(cornerRadius: 3)
                                .fill(ModelColorMap.color(for: entry.modelName).opacity(0.9))
                                .frame(width: max(2, proxy.size.width * CGFloat(fraction)))
                                .onHover { isHovered in
                                    hoveredModelName = isHovered ? entry.modelName : nil
                                }
                        }
                    }
                    .frame(height: 18, alignment: .leading)

                    if let hovered = hoveredModelName,
                       let entry = entries.first(where: { $0.modelName == hovered }) {
                        let pct = total > 0 ? entry.value / total * 100 : 0
                        Text("\(entry.displayName)  \(UsageFormatters.metricValue(entry.value, metric: metric))  \(String(format: "%.0f%%", pct))")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.black.opacity(0.88))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                                    )
                            )
                            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: 18)

            modelLegend(entries, total: total)
        }
        .padding(.horizontal, 4)
    }

    private func modelLegend(_ entries: [ModelUsageEntry], total: Double) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(entries.prefix(8))) { entry in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(ModelColorMap.color(for: entry.modelName))
                            .frame(width: 6, height: 6)
                        Text(entry.displayName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(height: 14)
    }

    @ViewBuilder
    private func modelBarChart(_ presentation: UsageHeatmapPresentation) -> some View {
        let dailyData = presentation.dailyModelData
        if !dailyData.isEmpty {
            modelTrendChartContent(
                dailyData: dailyData,
                modelOrder: presentation.modelEntries.map(\.modelName),
                modelEntries: presentation.modelEntries,
                modelTotalValue: presentation.modelTotalValue
            )
        }
    }

    private func modelTrendChartContent(dailyData: [ModelDailyEntry], modelOrder: [String], modelEntries: [ModelUsageEntry], modelTotalValue: Double) -> some View {
        let maxValue = max(dailyData.map(\.totalValue).max() ?? 0, 1)
        let chartHeight: CGFloat = 140
        let yAxisW: CGFloat = 48
        let xAxisHeight: CGFloat = 18
        let barSpacing: CGFloat = 1

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let chartWidth = geo.size.width - yAxisW - 8
                let barWidth = max(1, (chartWidth - barSpacing * CGFloat(max(dailyData.count - 1, 0))) / CGFloat(max(dailyData.count, 1)))

                HStack(spacing: 0) {
                    // Y-axis labels
                    yAxisLabels(maxValue: maxValue, chartHeight: chartHeight - xAxisHeight, labelWidth: yAxisW)

                    // Chart area
                    ZStack(alignment: .topLeading) {
                        // Grid lines + bars via Canvas
                        Canvas { context, size in
                            let drawHeight = size.height - xAxisHeight
                            let drawWidth = size.width

                            // Horizontal grid lines
                            let gridLines = 4
                            for i in 0...gridLines {
                                let y = drawHeight * CGFloat(i) / CGFloat(gridLines)
                                var gridPath = Path()
                                gridPath.move(to: CGPoint(x: 0, y: y))
                                gridPath.addLine(to: CGPoint(x: drawWidth, y: y))
                                context.stroke(gridPath, with: .color(Color.white.opacity(0.06)), lineWidth: 0.5)
                            }

                            // Stacked bars
                            for (dayIndex, day) in dailyData.enumerated() {
                                let barX = CGFloat(dayIndex) * (barWidth + barSpacing)
                                guard barX + barWidth > 0, barX < drawWidth else { continue }
                                let isSelected = day.localDate == selectedDateKey
                                let highlightRect = CGRect(x: barX, y: 0, width: barWidth, height: drawHeight)

                                if isSelected {
                                    context.fill(
                                        Path(highlightRect),
                                        with: .color(Color.white.opacity(0.05))
                                    )
                                }

                                var yOffset: CGFloat = 0
                                for modelName in modelOrder {
                                    guard let value = day.modelValues[modelName], value > 0 else { continue }
                                    let segHeight = CGFloat(value / maxValue) * drawHeight
                                    let rect = CGRect(
                                        x: barX,
                                        y: drawHeight - yOffset - segHeight,
                                        width: barWidth,
                                        height: segHeight
                                    )
                                    let path = Path(roundedRect: rect, cornerRadius: barWidth > 3 ? 1.5 : 0)
                                    context.fill(path, with: .color(ModelColorMap.color(for: modelName).opacity(0.9)))
                                    yOffset += segHeight
                                }

                                if isSelected {
                                    let selectedPath = Path(
                                        roundedRect: CGRect(
                                            x: barX,
                                            y: drawHeight - yOffset,
                                            width: barWidth,
                                            height: yOffset
                                        ),
                                        cornerRadius: barWidth > 3 ? 2 : 0
                                    )
                                    context.stroke(selectedPath, with: .color(Color.white.opacity(0.75)), lineWidth: 1.1)
                                }
                            }
                        }
                        .frame(width: chartWidth, height: chartHeight - xAxisHeight)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case let .active(location):
                                hoveredBarDay = hitBarDay(at: location, dailyData: dailyData, barWidth: barWidth, barSpacing: barSpacing)
                            case .ended:
                                hoveredBarDay = nil
                            }
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    guard let hit = hitBarDay(at: value.location, dailyData: dailyData, barWidth: barWidth, barSpacing: barSpacing) else { return }
                                    selectedDateKey = hit.day.localDate
                                }
                        )

                        // X-axis date labels (sparse)
                        HStack(spacing: 0) {
                            let labelInterval = max(1, dailyData.count / 6)
                            ForEach(Array(dailyData.enumerated()), id: \.offset) { index, day in
                                if index % labelInterval == 0 {
                                    Text(Self.shortDateFormatter.string(from: day.date))
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(.white.opacity(0.35))
                                        .frame(width: CGFloat(labelInterval) * (barWidth + barSpacing), alignment: .leading)
                                } else {
                                    Color.clear
                                        .frame(width: barWidth + barSpacing)
                                }
                            }
                        }
                        .frame(width: chartWidth, height: xAxisHeight)
                        .offset(y: chartHeight - xAxisHeight)

                        if let hoveredBarDay {
                            UsageHeatmapHoverTooltip(date: hoveredBarDay.day.date)
                                .frame(width: hoverTooltipWidth, height: hoverTooltipHeight)
                                .offset(
                                    x: barTooltipX(hoveredBarDay.dayIndex, barWidth: barWidth, barSpacing: barSpacing, chartWidth: chartWidth),
                                    y: 4
                                )
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: chartWidth, height: chartHeight)
                }
            }
            .frame(height: chartHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.035))
            )
            .padding(.horizontal, heatmapPadding)

            modelLegend(modelEntries, total: modelTotalValue)
        }
    }

    private func hitBarDay(at location: CGPoint, dailyData: [ModelDailyEntry], barWidth: CGFloat, barSpacing: CGFloat) -> ModelBarHover? {
        guard location.x >= 0, location.y >= 0 else { return nil }
        let pitch = barWidth + barSpacing
        guard pitch > 0 else { return nil }

        let dayIndex = Int(location.x / pitch)
        guard dayIndex >= 0, dayIndex < dailyData.count else { return nil }

        let localX = location.x - CGFloat(dayIndex) * pitch
        guard localX <= barWidth else { return nil }

        return ModelBarHover(dayIndex: dayIndex, day: dailyData[dayIndex])
    }

    private func barTooltipX(_ dayIndex: Int, barWidth: CGFloat, barSpacing: CGFloat, chartWidth: CGFloat) -> CGFloat {
        let barCenterX = CGFloat(dayIndex) * (barWidth + barSpacing) + barWidth / 2
        return min(max(0, barCenterX - hoverTooltipWidth / 2), max(0, chartWidth - hoverTooltipWidth))
    }

    private func yAxisLabels(maxValue: Double, chartHeight: CGFloat, labelWidth: CGFloat) -> some View {
        let gridLines = 4
        return VStack(spacing: 0) {
            ForEach(0...gridLines, id: \.self) { i in
                let value = maxValue * Double(gridLines - i) / Double(gridLines)
                Text(UsageFormatters.metricValue(value, metric: metric))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(width: labelWidth - 4, height: chartHeight / CGFloat(gridLines), alignment: .trailing)
            }
        }
        .frame(width: labelWidth)
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "M/d"
        return f
    }()

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

                        UsageHeatmapCanvasGrid(
                            weekColumns: weeks,
                            metric: metric,
                            maxValue: presentation.maxMetricValue,
                            selectedDateKey: $selectedDateKey,
                            hoveredCell: $hoveredCell,
                            cellSize: cellSize,
                            cellSpacing: cellSpacing
                        )
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
            HStack(alignment: .firstTextBaseline) {
                Text(selectedDateTitle(presentation.selectedDateKey))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))

                Spacer()

                DayMetricInline(bucket: presentation.selectedBucket)
            }

            if presentation.breakdownItems.isEmpty {
                Text(presentation.totalSessions == 0 ? "No usage data yet" : "No sessions on this day")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, minHeight: 86, alignment: .center)
            } else {
                projectBreakdown(presentation)
                breakdownList(presentation)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func projectBreakdown(_ presentation: UsageHeatmapPresentation) -> some View {
        HStack(spacing: 6) {
            ForEach(presentation.topProjects) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)

                    MetricValueCluster(
                        tokens: item.totalTokens,
                        costMicros: item.estimatedCostMicros,
                        sessions: item.sessionCount,
                        size: 9,
                        weight: .semibold
                    )
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

    private func breakdownList(_ presentation: UsageHeatmapPresentation) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 3) {
                ForEach(presentation.breakdownItems) { item in
                    UsageBreakdownRow(item: item)
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
        let dayBuckets = store.snapshot.days(for: agentFilter)
        let weekColumns = makeWeekColumns(dayBuckets)
        let rangeSummary = store.snapshot.summary(for: agentFilter)
        let selectedGroups = store.snapshot.groups(on: selectedDateKey, for: agentFilter)
        let topProjects = UsageAnalyticsAggregation.projectSummaries(from: selectedGroups)
            .prefix(3)
        let breakdownItems = UsageBreakdownItem.make(from: selectedGroups)

        let allGroups = store.snapshot.dayGroups.values
            .flatMap { $0 }
            .filter { agentFilter.includes($0.agent) }
        let modelEntries = Dictionary(grouping: allGroups) { $0.model ?? "unknown" }
            .map { modelName, groups -> ModelUsageEntry in
                ModelUsageEntry(
                    modelName: modelName,
                    displayName: modelName,
                    value: groups.reduce(0.0) { $0 + $1.value(for: metric) },
                    totalTokens: groups.reduce(0) { $0 + $1.totalTokens },
                    estimatedCostMicros: UsageAnalyticsAggregation.sumCostMicros(groups),
                    sessionCount: groups.reduce(0) { $0 + $1.sessionCount }
                )
            }
            .sorted { $0.value > $1.value }
        let modelTotalValue = modelEntries.reduce(0.0) { $0 + $1.value }

        // Build per-date per-model data for trend chart
        let dailyModelData: [ModelDailyEntry] = dayBuckets.compactMap { bucket in
            let dayGroups = store.snapshot.dayGroups[bucket.localDate]?
                .filter { agentFilter.includes($0.agent) } ?? []
            guard !dayGroups.isEmpty else { return nil }
            let modelValues = Dictionary(grouping: dayGroups, by: { $0.model ?? "unknown" })
                .mapValues { groups in groups.reduce(0.0) { $0 + $1.value(for: metric) } }
            return ModelDailyEntry(localDate: bucket.localDate, date: bucket.date, modelValues: modelValues)
        }

        return UsageHeatmapPresentation(
            selectedDateKey: selectedDateKey,
            totalTokens: rangeSummary.totalTokens,
            totalCostMicros: rangeSummary.estimatedCostMicros,
            totalSessions: rangeSummary.sessionCount,
            weekColumns: weekColumns,
            monthLabels: makeMonthLabels(weekColumns),
            maxMetricValue: max(dayBuckets.map { $0.value(for: metric) }.max() ?? 0, 1),
            selectedBucket: dayBuckets.first { $0.localDate == selectedDateKey } ?? emptyBucket(for: selectedDateKey),
            topProjects: Array(topProjects),
            breakdownItems: breakdownItems,
            modelEntries: modelEntries,
            modelTotalValue: modelTotalValue,
            dailyModelData: dailyModelData
        )
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
    let topProjects: [UsageProjectUsageSummary]
    let breakdownItems: [UsageBreakdownItem]
    let modelEntries: [ModelUsageEntry]
    let modelTotalValue: Double
    let dailyModelData: [ModelDailyEntry]
}

private struct UsageBreakdownItem: Identifiable {
    let id: String
    let agent: UsageAnalyticsAgent
    let projectName: String
    let model: String?
    let isSidechain: Bool
    let totalTokens: Int64
    let estimatedCostMicros: Int64?
    let sessionCount: Int

    static func make(from groups: [UsageDayGroupRecord]) -> [UsageBreakdownItem] {
        groups.map { group in
            UsageBreakdownItem(
                id: group.id,
                agent: group.agent,
                projectName: group.projectName,
                model: group.model,
                isSidechain: group.isSidechain,
                totalTokens: group.totalTokens,
                estimatedCostMicros: group.estimatedCostMicros,
                sessionCount: group.sessionCount
            )
        }
        .sorted {
            switch ($0.estimatedCostMicros, $1.estimatedCostMicros) {
            case let (lhs?, rhs?) where lhs != rhs:
                return lhs > rhs
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return $0.totalTokens > $1.totalTokens
            }
        }
    }
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

private struct UsageHeatmapCanvasGrid: View {
    let weekColumns: [[UsageDayBucket?]]
    let metric: UsageAnalyticsMetric
    let maxValue: Double
    @Binding var selectedDateKey: String
    @Binding var hoveredCell: UsageHeatmapHover?
    let cellSize: CGFloat
    let cellSpacing: CGFloat

    var body: some View {
        Canvas { context, _ in
            for (weekIndex, days) in weekColumns.enumerated() {
                for dayIndex in 0..<7 {
                    guard dayIndex < days.count, let day = days[dayIndex] else {
                        continue
                    }

                    let rect = CGRect(
                        x: CGFloat(weekIndex) * (cellSize + cellSpacing),
                        y: CGFloat(dayIndex) * (cellSize + cellSpacing),
                        width: cellSize,
                        height: cellSize
                    )
                    let path = Path(roundedRect: rect, cornerRadius: 2.5)
                    context.fill(path, with: .color(fillColor(for: day)))
                    context.stroke(
                        path,
                        with: .color(strokeColor(for: day)),
                        lineWidth: day.localDate == selectedDateKey ? 1.2 : 0.5
                    )
                }
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case let .active(location):
                hoveredCell = hitCell(at: location)
            case .ended:
                hoveredCell = nil
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    guard let hit = hitCell(at: value.location) else { return }
                    selectedDateKey = hit.day.localDate
                }
        )
    }

    private func hitCell(at location: CGPoint) -> UsageHeatmapHover? {
        guard location.x >= 0, location.y >= 0 else { return nil }
        let pitch = cellSize + cellSpacing
        guard pitch > 0 else { return nil }

        let weekIndex = Int(location.x / pitch)
        let dayIndex = Int(location.y / pitch)
        guard weekIndex >= 0,
              weekIndex < weekColumns.count,
              dayIndex >= 0,
              dayIndex < 7 else {
            return nil
        }

        let localX = location.x - CGFloat(weekIndex) * pitch
        let localY = location.y - CGFloat(dayIndex) * pitch
        guard localX <= cellSize, localY <= cellSize,
              dayIndex < weekColumns[weekIndex].count,
              let day = weekColumns[weekIndex][dayIndex] else {
            return nil
        }

        return UsageHeatmapHover(weekIndex: weekIndex, dayIndex: dayIndex, day: day)
    }

    private func fillColor(for day: UsageDayBucket) -> Color {
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

    private func strokeColor(for day: UsageDayBucket) -> Color {
        day.localDate == selectedDateKey ? Color.white.opacity(0.75) : Color.white.opacity(0.08)
    }
}

private struct UsageHeatmapHoverTooltip: View {
    let date: Date

    init(day: UsageDayBucket) {
        self.date = day.date
    }

    init(date: Date) {
        self.date = date
    }

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
        UsageHeatmapHoverTooltip.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
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

private struct DayMetricInline: View {
    let bucket: UsageDayBucket

    var body: some View {
        MetricValueCluster(
            tokens: bucket.totalTokens,
            costMicros: bucket.estimatedCostMicros,
            sessions: bucket.sessionCount,
            size: 12,
            weight: .semibold
        )
    }
}

private struct MetricValueCluster: View {
    let tokens: Int64
    let costMicros: Int64?
    let sessions: Int
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        HStack(spacing: 8) {
            metricText(UsageFormatters.compactTokens(tokens), color: TerminalColors.green)
            metricText(UsageDetailFormatters.cost(costMicros), color: TerminalColors.amber)
            metricText("\(sessions)", color: TerminalColors.blue)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func metricText(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.system(size: size, weight: weight, design: .monospaced))
            .foregroundColor(color.opacity(0.9))
    }
}

private struct UsageBreakdownRow: View {
    let item: UsageBreakdownItem

    var body: some View {
        HStack(spacing: 8) {
            AgentLogoIcon(kind: item.agent == .claude ? .claude : .codex, size: 13)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(item.projectName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.78))
                        .lineLimit(1)

                    if item.isSidechain {
                        Text("Sub")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }

                Text(item.model ?? "Unknown model")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.32))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(UsageFormatters.compactTokens(item.totalTokens))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(TerminalColors.green.opacity(0.68))
                HStack(spacing: 6) {
                    Text(UsageDetailFormatters.cost(item.estimatedCostMicros))
                        .foregroundColor(TerminalColors.amber.opacity(0.62))
                    Text("\(item.sessionCount)")
                        .foregroundColor(TerminalColors.blue.opacity(0.68))
                }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
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

private enum UsageDetailFormatters {
    static func cost(_ micros: Int64?) -> String {
        guard let micros else { return "--" }
        return String(format: "$%.2f", Double(micros) / 1_000_000)
    }
}

private struct ModelUsageEntry: Identifiable {
    let modelName: String
    let displayName: String
    let value: Double
    let totalTokens: Int64
    let estimatedCostMicros: Int64?
    let sessionCount: Int
    var id: String { modelName }
}

private struct ModelDailyEntry {
    let localDate: String
    let date: Date
    let modelValues: [String: Double]
    var totalValue: Double { modelValues.values.reduce(0, +) }
}

private struct ModelBarHover {
    let dayIndex: Int
    let day: ModelDailyEntry
}

private enum ModelColorMap {
    static func color(for modelName: String) -> Color {
        let lower = modelName.lowercased()

        if lower.contains("gpt-5.5-pro") { return rgb(0.54, 0.72, 1.00) }
        if lower.contains("gpt-5.5") { return TerminalColors.blue }
        if lower.contains("gpt-5.4-mini") { return rgb(0.24, 0.82, 0.72) }
        if lower.contains("gpt-5.4") { return TerminalColors.green }
        if lower.contains("gpt-5.3-codex") { return rgb(0.62, 0.50, 1.00) }
        if lower.contains("gpt-5.3") { return rgb(0.36, 0.78, 0.92) }
        if lower.contains("gpt") { return rgb(0.42, 0.68, 1.00) }

        if lower.contains("opus") { return rgb(0.78, 0.44, 0.86) }
        if lower.contains("sonnet") { return rgb(0.88, 0.48, 0.62) }
        if lower.contains("haiku") { return rgb(0.56, 0.70, 1.00) }

        if lower.contains("deepseek") { return rgb(0.36, 0.78, 0.58) }
        if lower.contains("glm") { return TerminalColors.prompt }
        if lower.contains("qwen") { return rgb(0.70, 0.56, 1.00) }
        if lower.contains("kimi") { return TerminalColors.amber }
        if lower.contains("minimax") { return rgb(0.26, 0.78, 0.78) }

        return fallbackColor(for: modelName)
    }

    private static let fallbackPalette: [Color] = [
        TerminalColors.green,
        TerminalColors.amber,
        TerminalColors.blue,
        rgb(0.24, 0.82, 0.72),
        rgb(0.78, 0.44, 0.86),
        TerminalColors.prompt,
    ]

    private static func fallbackColor(for name: String) -> Color {
        let index = abs(name.hashValue) % fallbackPalette.count
        return fallbackPalette[index]
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red, green: green, blue: blue)
    }
}

private enum UsageChartMode: String, CaseIterable, Identifiable {
    case heatmap
    case stackedBar
    case barChart

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .heatmap: return "Heatmap"
        case .stackedBar: return "Stack"
        case .barChart: return "Bars"
        }
    }
}
