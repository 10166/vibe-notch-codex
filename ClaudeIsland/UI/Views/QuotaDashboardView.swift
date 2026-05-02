//
//  QuotaDashboardView.swift
//  ClaudeIsland
//
//  API usage quota dashboard for Claude Code and Codex CLI.
//

import SwiftUI

struct QuotaDashboardView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var store = QuotaStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(QuotaProvider.allCases) { provider in
                        if let index = QuotaProvider.allCases.firstIndex(of: provider), index > 0 {
                            Divider()
                                .background(Color.white.opacity(0.08))
                                .padding(.horizontal, 12)
                        }
                        QuotaProviderCard(
                            snapshot: store.snapshot.providers[provider]
                        )
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            store.start()
        }
        .onDisappear {
            store.stop()
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

            Text("API Quota")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .scaleEffect(0.45)
                    .frame(width: 16, height: 16)
            }

            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Provider Card

private struct QuotaProviderCard: View {
    let snapshot: QuotaProviderSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(providerName.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if let snapshot {
                providerContent(snapshot)
            } else {
                noDataView
            }
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func providerContent(_ snapshot: QuotaProviderSnapshot) -> some View {
        if let error = snapshot.error {
            errorView(error)
        } else {
            windowsSection(snapshot)
            identitySection(snapshot)
            creditsSection(snapshot)
        }
    }

    @ViewBuilder
    private func windowsSection(_ snapshot: QuotaProviderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let primary = snapshot.primary {
                QuotaProgressBar(window: primary)
            }
            if let secondary = snapshot.secondary {
                QuotaProgressBar(window: secondary)
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func identitySection(_ snapshot: QuotaProviderSnapshot) -> some View {
        if let identity = snapshot.identity {
            let parts = [identity.email, identity.plan].compactMap { $0 }
            if !parts.isEmpty {
                Text(parts.joined(separator: " | "))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.horizontal, 12)
            }
        }
    }

    @ViewBuilder
    private func creditsSection(_ snapshot: QuotaProviderSnapshot) -> some View {
        if let credits = snapshot.credits, credits.hasCredits, let balance = credits.balance {
            Text(credits.unlimited
                    ? "Credits: Unlimited"
                    : String(format: "Credits: $%.2f", balance))
                .font(.system(size: 11))
                .foregroundColor(TerminalColors.green.opacity(0.8))
                .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private func errorView(_ error: QuotaError) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TerminalColors.amber.opacity(0.8))
                Text(errorTitle(error))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            Text(errorMessage(error))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 12)
    }

    private var noDataView: some View {
        Text("No data available")
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.4))
            .padding(.horizontal, 12)
    }

    private var providerName: String {
        snapshot?.provider.displayName ?? "Unknown"
    }

    private func errorTitle(_ error: QuotaError) -> String {
        switch error {
        case .noCredentials: return "No credentials found"
        case .networkError: return "Network error"
        case .unauthorized: return "Unauthorized"
        case .invalidResponse: return "Invalid response"
        case .notAvailable: return "Not available"
        }
    }

    private func errorMessage(_ error: QuotaError) -> String {
        switch error {
        case .noCredentials:
            let name = snapshot?.provider.displayName ?? "the CLI"
            return "Run `\(name.lowercased())` to authenticate"
        case .networkError(let detail):
            return detail
        case .unauthorized:
            return "Your session has expired. Please re-authenticate."
        case .invalidResponse:
            return "Could not parse the quota response."
        case .notAvailable:
            return "Quota information is not available at this time."
        }
    }
}

// MARK: - Progress Bar

private struct QuotaProgressBar: View {
    let window: QuotaRateWindow

    private var usageColor: Color {
        QuotaFormatters.colorForUsage(window.usedPercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(QuotaFormatters.windowLabel(window))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                Text(QuotaFormatters.usagePercent(window))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(usageColor)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)

                    Capsule()
                        .fill(usageColor.opacity(0.85))
                        .frame(
                            width: max(0, geometry.size.width * CGFloat(window.remainingPercent / 100)),
                            height: 6
                        )
                }
            }
            .frame(height: 6)

            if let resetsAt = window.resetsAt {
                Text("Resets in \(QuotaFormatters.resetCountdown(from: resetsAt, now: Date()))")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            } else if let description = window.resetDescription {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }
}
