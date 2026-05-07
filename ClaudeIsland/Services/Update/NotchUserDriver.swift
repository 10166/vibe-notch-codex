//
//  NotchUserDriver.swift
//  ClaudeIsland
//
//  Custom Sparkle user driver for in-notch update UI
//

import AppKit
import Combine
import Foundation
import Sparkle

private struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

/// Update state published to UI
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case found(version: String, releaseNotes: String?)
    case downloading(progress: Double)  // 0.0 to 1.0
    case extracting(progress: Double)
    case readyToInstall(version: String)
    case installing
    case error(message: String)

    var isActive: Bool {
        switch self {
        case .idle, .upToDate, .error:
            return false
        default:
            return true
        }
    }
}

/// Observable update manager that bridges Sparkle to SwiftUI
@MainActor
class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    @Published var state: UpdateState = .idle
    @Published var hasUnseenUpdate: Bool = false
    private var hasSeenUpdateThisSession: Bool = false

    private var downloadedBytes: Int64 = 0
    private var expectedBytes: Int64 = 0
    private var currentVersion: String = ""
    private var manualDownloadURL: URL?
    private var fallbackTask: Task<Void, Never>?

    // Callbacks from Sparkle
    private var installHandler: ((SPUUserUpdateChoice) -> Void)?
    private var cancellationHandler: (() -> Void)?

    override init() {
        super.init()
    }

    // MARK: - Public API

    func checkForUpdates() {
        state = .checking
        manualDownloadURL = nil
        fallbackTask?.cancel()

        guard let updater = AppDelegate.shared?.updater, updater.canCheckForUpdates else {
            checkGitHubReleaseFallback(sparkleError: "Updater not initialized")
            return
        }

        updater.checkForUpdates()
    }

    func downloadAndInstall() {
        if let manualDownloadURL {
            NSWorkspace.shared.open(manualDownloadURL)
            state = .idle
            return
        }

        installHandler?(.install)
    }

    func installAndRelaunch() {
        installHandler?(.install)
    }

    func skipUpdate() {
        installHandler?(.skip)
        state = .idle
    }

    func dismissUpdate() {
        installHandler?(.dismiss)
        state = .idle
    }

    func cancelDownload() {
        cancellationHandler?()
        state = .idle
    }

    // MARK: - Internal state updates (called by NotchUserDriver)

    func updateFound(version: String, releaseNotes: String?, installHandler: @escaping (SPUUserUpdateChoice) -> Void) {
        self.currentVersion = version
        self.installHandler = installHandler
        self.manualDownloadURL = nil
        self.state = .found(version: version, releaseNotes: releaseNotes)
        // Only show the dot if user hasn't seen it this session
        if !hasSeenUpdateThisSession {
            self.hasUnseenUpdate = true
        }
    }

    func markUpdateSeen() {
        self.hasUnseenUpdate = false
        self.hasSeenUpdateThisSession = true
    }

    func downloadStarted(cancellation: @escaping () -> Void) {
        self.cancellationHandler = cancellation
        self.downloadedBytes = 0
        self.expectedBytes = 0
        self.state = .downloading(progress: 0)
    }

    func downloadExpectedLength(_ length: UInt64) {
        self.expectedBytes = Int64(length)
    }

    func downloadReceivedData(_ length: UInt64) {
        self.downloadedBytes += Int64(length)
        let progress = expectedBytes > 0 ? Double(downloadedBytes) / Double(expectedBytes) : 0
        self.state = .downloading(progress: min(progress, 1.0))
    }

    func extractionStarted() {
        self.state = .extracting(progress: 0)
    }

    func extractionProgress(_ progress: Double) {
        self.state = .extracting(progress: progress)
    }

    func readyToInstall(installHandler: @escaping (SPUUserUpdateChoice) -> Void) {
        self.installHandler = installHandler
        self.state = .readyToInstall(version: currentVersion)
    }

    func installing() {
        self.state = .installing
    }

    func installed(relaunched: Bool) {
        self.state = .idle
    }

    func noUpdateFound() {
        self.manualDownloadURL = nil
        self.state = .upToDate
        // Reset to idle after a few seconds
        Task {
            try? await Task.sleep(for: .seconds(5))
            if case .upToDate = self.state {
                self.state = .idle
            }
        }
    }

    func updateError(_ message: String) {
        checkGitHubReleaseFallback(sparkleError: message)
    }

    func dismiss() {
        // Don't dismiss if we're showing "up to date" - let it display
        if case .upToDate = state {
            return
        }
        self.state = .idle
        self.installHandler = nil
        self.cancellationHandler = nil
        self.manualDownloadURL = nil
        self.fallbackTask?.cancel()
        self.fallbackTask = nil
    }

    private func checkGitHubReleaseFallback(sparkleError: String) {
        fallbackTask?.cancel()
        fallbackTask = Task {
            do {
                let release = try await Self.fetchLatestGitHubRelease()
                guard !Task.isCancelled else { return }
                applyGitHubFallback(release, sparkleError: sparkleError)
            } catch {
                guard !Task.isCancelled else { return }
                state = .error(message: sparkleError.isEmpty ? error.localizedDescription : sparkleError)
            }
        }
    }

    private func applyGitHubFallback(_ release: GitHubRelease, sparkleError: String) {
        let latestVersion = Self.normalizedVersion(release.tagName)
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        guard Self.isVersion(latestVersion, newerThan: currentVersion) else {
            noUpdateFound()
            return
        }

        guard let dmgAsset = release.assets.first(where: { asset in
            let lowercasedName = asset.name.lowercased()
            return lowercasedName.hasSuffix(".dmg")
        }) else {
            state = .error(message: sparkleError.isEmpty ? "No downloadable update found" : sparkleError)
            return
        }

        self.currentVersion = latestVersion
        self.installHandler = nil
        self.manualDownloadURL = dmgAsset.browserDownloadURL
        self.state = .found(version: latestVersion, releaseNotes: release.body)

        if !hasSeenUpdateThisSession {
            self.hasUnseenUpdate = true
        }
    }

    private static func fetchLatestGitHubRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/10166/vibe-notch-codex/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Vibe-Notch", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    nonisolated private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = numericVersionParts(candidate)
        let currentParts = numericVersionParts(current)
        let maxCount = max(candidateParts.count, currentParts.count)

        for index in 0..<maxCount {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0

            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }

        return false
    }

    nonisolated private static func numericVersionParts(_ version: String) -> [Int] {
        normalizedVersion(version)
            .split(separator: ".")
            .map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }

    nonisolated private static func normalizedVersion(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }
}

/// Custom Sparkle user driver that routes all UI to NotchUpdateManager
class NotchUserDriver: NSObject, SPUUserDriver {

    var canCheckForUpdates: Bool { true }

    // MARK: - Update Found

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Auto-approve update checks
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        Task { @MainActor in
            UpdateManager.shared.state = .checking
        }
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let version = appcastItem.displayVersionString
        let releaseNotes = appcastItem.itemDescription

        Task { @MainActor in
            UpdateManager.shared.updateFound(version: version, releaseNotes: releaseNotes, installHandler: reply)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        // Release notes downloaded - we already have them from appcastItem
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        // Ignore release notes failures
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        Task { @MainActor in
            UpdateManager.shared.noUpdateFound()
        }
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        Task { @MainActor in
            UpdateManager.shared.updateError(error.localizedDescription)
        }
        acknowledgement()
    }

    // MARK: - Download Progress

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        Task { @MainActor in
            UpdateManager.shared.downloadStarted(cancellation: cancellation)
        }
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        Task { @MainActor in
            UpdateManager.shared.downloadExpectedLength(expectedContentLength)
        }
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        Task { @MainActor in
            UpdateManager.shared.downloadReceivedData(length)
        }
    }

    func showDownloadDidStartExtractingUpdate() {
        Task { @MainActor in
            UpdateManager.shared.extractionStarted()
        }
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        Task { @MainActor in
            UpdateManager.shared.extractionProgress(progress)
        }
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        Task { @MainActor in
            UpdateManager.shared.readyToInstall(installHandler: reply)
        }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        Task { @MainActor in
            UpdateManager.shared.installing()
        }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        Task { @MainActor in
            UpdateManager.shared.installed(relaunched: relaunched)
        }
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        Task { @MainActor in
            UpdateManager.shared.dismiss()
        }
    }

    // MARK: - Resume/Focus

    func showUpdateInFocus() {
        // Could expand notch here if desired
    }

    func showResumableUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // Resumable update - treat same as regular update found
        showUpdateFound(with: appcastItem, state: state, reply: reply)
    }

    func showInformationalUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // Informational only - dismiss for now
        reply(.dismiss)
    }
}
