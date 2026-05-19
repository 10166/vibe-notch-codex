//
//  UsageShareImageGenerator.swift
//  ClaudeIsland
//
//  Generates a shareable usage analytics image for clipboard.
//

import AppKit
import SwiftUI

enum UsageShareImageGenerator {
    @MainActor
    static func generateAndCopy(
        presentation: UsageHeatmapPresentation,
        metric: UsageAnalyticsMetric,
        agentFilter: UsageAnalyticsAgentFilter,
        range: UsageAnalyticsRange,
        chartMode: UsageChartMode
    ) -> Bool {
        let card = UsageShareCard(
            presentation: presentation,
            metric: metric,
            agentFilter: agentFilter,
            range: range,
            chartMode: chartMode
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2.0
        guard let image = renderer.nsImage else { return false }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        return true
    }
}

// MARK: - Share Card

private struct UsageShareCard: View {
    let presentation: UsageHeatmapPresentation
    let metric: UsageAnalyticsMetric
    let agentFilter: UsageAnalyticsAgentFilter
    let range: UsageAnalyticsRange
    let chartMode: UsageChartMode

    private let chartWidth: CGFloat = 380
    private let statsWidth: CGFloat = 150
    private let cellSpacing: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 10)

            Divider().background(Color.white.opacity(0.08))
                .padding(.bottom, 10)

            HStack(alignment: .center, spacing: 18) {
                chartContent
                statsColumn
            }

            Divider().background(Color.white.opacity(0.06))
                .padding(.top, 10)
                .padding(.bottom, 8)

            footer
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18))
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .fixedSize()
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Vibe Notch")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.92))
            Text("  ")
            HStack(spacing: 5) {
                metaTag("Usage Analytics")
                Text("\u{00b7}").foregroundColor(.white.opacity(0.2))
                metaTag(range.displayName)
                Text("\u{00b7}").foregroundColor(.white.opacity(0.2))
                metaTag(agentFilter.displayName)
            }
            Spacer()
        }
    }

    private func metaTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.42))
    }

    // MARK: - Chart Content

    @ViewBuilder
    private var chartContent: some View {
        switch chartMode {
        case .heatmap:
            heatmapSection
        case .stackedBar:
            stackedBarSection
        case .barChart:
            barChartSection
        }
    }

    // MARK: Heatmap

    private var heatmapSection: some View {
        let weeks = presentation.weekColumns
        let weekCount = max(weeks.count, 1)
        let cellSize = min(16, max(5, (chartWidth - CGFloat(max(weekCount - 1, 0)) * cellSpacing) / CGFloat(weekCount)))
        let gridW = CGFloat(weekCount) * (cellSize + cellSpacing) - cellSpacing
        let gridH = 7 * (cellSize + cellSpacing) - cellSpacing

        return Canvas { ctx, _ in
            for (wi, days) in weeks.enumerated() {
                for di in 0..<7 where di < days.count {
                    guard let day = days[di] else { continue }
                    let rect = CGRect(
                        x: CGFloat(wi) * (cellSize + cellSpacing),
                        y: CGFloat(di) * (cellSize + cellSpacing),
                        width: cellSize, height: cellSize
                    )
                    let path = Path(roundedRect: rect, cornerRadius: 2.5)
                    ctx.fill(path, with: .color(cellColor(day)))
                    ctx.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
                }
            }
        }
        .frame(width: gridW, height: gridH)
    }

    private func cellColor(_ day: UsageDayBucket) -> Color {
        let value = day.value(for: metric)
        guard value > 0 else { return .white.opacity(0.06) }
        let n = min(max(value / presentation.maxMetricValue, 0), 1)
        let opacity = 0.22 + n * 0.7
        switch metric {
        case .tokens:   return TerminalColors.green.opacity(opacity)
        case .cost:     return TerminalColors.amber.opacity(opacity)
        case .sessions: return TerminalColors.blue.opacity(opacity)
        }
    }

    // MARK: Stacked Bar

    @ViewBuilder
    private var stackedBarSection: some View {
        if presentation.modelTotalValue > 0, !presentation.modelEntries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Canvas { ctx, size in
                    let entries = presentation.modelEntries
                    let total = presentation.modelTotalValue
                    let w = size.width
                    let gapCount = max(entries.count - 1, 0)
                    let totalGap = CGFloat(gapCount) * 1.5
                    let usable = w - totalGap
                    var x: CGFloat = 0
                    for entry in entries {
                        let segW = max(2, usable * CGFloat(entry.value / total))
                        let rect = CGRect(x: x, y: 0, width: segW, height: size.height)
                        ctx.fill(
                            Path(roundedRect: rect, cornerRadius: 4),
                            with: .color(ModelColorMap.color(for: entry.modelName).opacity(0.9))
                        )
                        x += segW + 1.5
                    }
                }
                .frame(width: chartWidth, height: 60)

                legendRow(presentation.modelEntries)
            }
        }
    }

    // MARK: Bar Chart

    @ViewBuilder
    private var barChartSection: some View {
        if !presentation.dailyModelData.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Canvas { ctx, size in
                    let dailyData = presentation.dailyModelData
                    let modelOrder = presentation.modelEntries.map(\.modelName)
                    let maxVal = max(dailyData.map(\.totalValue).max() ?? 0, 1)
                    let drawH = size.height
                    let drawW = size.width
                    let barSp: CGFloat = 1
                    let barW = max(1, (drawW - barSp * CGFloat(max(dailyData.count - 1, 0))) / CGFloat(max(dailyData.count, 1)))

                    for i in 0...4 {
                        let y = drawH * CGFloat(i) / 4
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: drawW, y: y))
                        ctx.stroke(p, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
                    }

                    for (di, day) in dailyData.enumerated() {
                        let barX = CGFloat(di) * (barW + barSp)
                        guard barX + barW > 0, barX < drawW else { continue }
                        var yOff: CGFloat = 0
                        for model in modelOrder {
                            guard let v = day.modelValues[model], v > 0 else { continue }
                            let segH = CGFloat(v / maxVal) * drawH
                            let rect = CGRect(x: barX, y: drawH - yOff - segH, width: barW, height: segH)
                            ctx.fill(
                                Path(roundedRect: rect, cornerRadius: barW > 3 ? 1.5 : 0),
                                with: .color(ModelColorMap.color(for: model).opacity(0.9))
                            )
                            yOff += segH
                        }
                    }
                }
                .frame(width: chartWidth, height: 180)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))

                legendRow(presentation.modelEntries)
            }
        }
    }

    // MARK: - Stats Column

    private var statsColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            statItem(
                label: "Tokens",
                value: UsageFormatters.compactTokens(presentation.totalTokens),
                color: TerminalColors.green
            )

            Spacer().frame(height: 14)

            statItem(
                label: "Cost",
                value: UsageFormatters.cost(presentation.totalCostMicros),
                color: TerminalColors.amber
            )

            Spacer().frame(height: 14)

            statItem(
                label: "Sessions",
                value: "\(presentation.totalSessions)",
                color: TerminalColors.blue
            )
        }
        .frame(width: statsWidth)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Today  ")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.35))
            + Text(UsageFormatters.compactTokens(todayBucket.totalTokens))
                .foregroundColor(TerminalColors.green.opacity(0.7))
            + Text("  \u{00b7}  ")
                .foregroundColor(.white.opacity(0.2))
            + Text(UsageFormatters.cost(todayBucket.estimatedCostMicros))
                .foregroundColor(TerminalColors.amber.opacity(0.7))
            + Text("  \u{00b7}  ")
                .foregroundColor(.white.opacity(0.2))
            + Text(todayBucket.sessionCount == 1 ? "1 session" : "\(todayBucket.sessionCount) sessions")
                .foregroundColor(TerminalColors.blue.opacity(0.7))

            Spacer()

            Text("github.com/10166/vibe-notch-codex")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.2))
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
    }

    private static let todayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var todayBucket: UsageDayBucket {
        let key = Self.todayKeyFormatter.string(from: Date())
        for week in presentation.weekColumns {
            for day in week {
                if let day, day.localDate == key { return day }
            }
        }
        return UsageDayBucket(
            localDate: key, date: Date(),
            inputTokens: 0, outputTokens: 0,
            cacheReadTokens: 0, cacheCreationTokens: 0,
            estimatedCostMicros: nil, sessionCount: 0
        )
    }

    // MARK: - Helpers

    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.38))
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func legendRow(_ entries: [ModelUsageEntry]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(entries.prefix(6))) { entry in
                HStack(spacing: 2) {
                    Circle()
                        .fill(ModelColorMap.color(for: entry.modelName))
                        .frame(width: 4, height: 4)
                    Text(entry.displayName)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.42))
                        .lineLimit(1)
                }
            }
        }
    }
}
