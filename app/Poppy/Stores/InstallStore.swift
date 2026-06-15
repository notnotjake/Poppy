import AppKit
import Combine
import Foundation
import SwiftData

@MainActor
final class InstallStore: ObservableObject {
    private static let watchedFolderPathKey = "watchedFolderPath"
    private static let installFolderPathKey = "installFolderPath"
    private static let hiddenInstallablePathsKey = "hiddenInstallablePaths"

    @Published var currentJob: InstallJob?
    @Published private(set) var installableItems: [InstallableItem] = []
    @Published private(set) var hiddenInstallableItems: [InstallableItem] = []
    @Published private(set) var debugAppItems: [AppItem] = []
    @Published private(set) var diagnosticLogEntries: [DiagnosticLogEntry] = []
    @Published var records: [InstallRecord] = []
    @Published var isWatching = false
    @Published private(set) var watchedFolderURL: URL
    @Published private(set) var installFolderURL: URL

    private var queuedJobs: [InstallJob] = []
    private var activeInstallTask: Task<Void, Never>?
    private var watcher: DownloadsWatcher?
    private var hiddenInstallableURLs = Set<URL>()
    private var zipInstallableCache = [URL: ZipInstallableCacheEntry]()
    private var zipInspectionTasks = Set<URL>()
    private var zipRetryStates = [URL: ZipRetryState]()
    private var appBundleSizeCache = [URL: AppBundleSizeCacheEntry]()
    private var appBundleSizeTasks = Set<URL>()
    private let maxInstallReadinessStableRetries = 5
    private let modelContext: ModelContext?

    private static var detectedInstallApprovalBehavior: InstallJob.ApprovalBehavior {
        if UserDefaults.standard.bool(forKey: AutoInstallDetectedApplications.storageKey) {
            return .autoInstall(afterSeconds: AutoInstallDetectedApplications.delaySeconds)
        }

        return .manual
    }

    static var defaultWatchedFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    static var defaultInstallFolderURL: URL {
        URL(fileURLWithPath: "/Applications", isDirectory: true)
    }

    var defaultWatchedFolderURL: URL { Self.defaultWatchedFolderURL }
    var defaultInstallFolderURL: URL { Self.defaultInstallFolderURL }

    init() {
        modelContext = Self.makeModelContext()

        if let storedPath = UserDefaults.standard.string(forKey: Self.watchedFolderPathKey), !storedPath.isEmpty {
            watchedFolderURL = URL(fileURLWithPath: storedPath, isDirectory: true)
        } else {
            watchedFolderURL = Self.defaultWatchedFolderURL
        }

        if let storedPath = UserDefaults.standard.string(forKey: Self.installFolderPathKey), !storedPath.isEmpty {
            installFolderURL = URL(fileURLWithPath: storedPath, isDirectory: true)
        } else {
            installFolderURL = Self.defaultInstallFolderURL
        }

        hiddenInstallableURLs = Self.loadHiddenInstallableURLs()
        records = Self.loadRecords(from: modelContext)
    }

    func start() {
        guard watcher == nil else { return }
        scanWatchedFolder()
        watcher = DownloadsWatcher(
            downloadsURL: watchedFolderURL,
            onDetected: { [weak self] sourceURL in
                self?.handleDetectedInstallable(
                    sourceURL,
                    approvalBehavior: Self.detectedInstallApprovalBehavior
                )
            },
            onChanged: { [weak self] in
                self?.scanWatchedFolder()
            },
            onLog: { [weak self] message in
                self?.addDiagnosticLog(message)
            }
        )
        watcher?.start()
        isWatching = true
    }

    func stop() {
        addDiagnosticLog("Stopping watcher")
        watcher?.stop()
        watcher = nil
        isWatching = false
    }

    func chooseWatchedFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Watch Folder"
        panel.message = "Poppy will watch this folder for app installers."
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = watchedFolderURL

        presentFolderPanel(panel) { [weak self] response in
            guard response == .OK, let folderURL = panel.url else {
                return
            }

            Task { @MainActor in
                self?.setWatchedFolder(folderURL)
            }
        }
    }

    func setWatchedFolder(_ folderURL: URL) {
        let wasWatching = isWatching
        stop()
        watchedFolderURL = folderURL
        UserDefaults.standard.set(folderURL.path, forKey: Self.watchedFolderPathKey)
        queuedJobs.removeAll()
        currentJob = nil
        activeInstallTask?.cancel()
        activeInstallTask = nil
        scanWatchedFolder()

        if wasWatching {
            start()
        }
    }

    func chooseInstallFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Install Folder"
        panel.message = "Installed apps will be copied into this folder."
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = installFolderURL

        presentFolderPanel(panel) { [weak self] response in
            guard response == .OK, let folderURL = panel.url else {
                return
            }

            Task { @MainActor in
                self?.setInstallFolder(folderURL)
            }
        }
    }

    func setInstallFolder(_ folderURL: URL) {
        installFolderURL = folderURL
        UserDefaults.standard.set(folderURL.path, forKey: Self.installFolderPathKey)
        scanWatchedFolder()
    }

    func resetWatchedFolder() {
        setWatchedFolder(defaultWatchedFolderURL)
    }

    func resetInstallFolder() {
        setInstallFolder(defaultInstallFolderURL)
    }

    func openWatchedFolder() {
        NSWorkspace.shared.open(watchedFolderURL)
    }

    func openInstallFolder() {
        NSWorkspace.shared.open(installFolderURL)
    }

    private func presentFolderPanel(_ panel: NSOpenPanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        panel.begin(completionHandler: completion)
    }

    func promptForLatestInstallableInWatchedFolder() {
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: watchedFolderURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }

        let latestInstallable = urls
            .filter { shouldShowInstallable($0) && !isHiddenInstallable($0) }
            .sorted {
                let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
            .first

        if let latestInstallable {
            handleDetectedInstallable(latestInstallable)
        }
    }

    func approveCurrentInstall() {
        guard let job = currentJob else { return }
        install(job: job)
    }

    func installNow(_ item: InstallableItem) {
        installNow(sourceURL: item.url)
    }

    func installNow(sourceURL: URL) {
        guard !isInstalling(sourceURL) else { return }
        removeHiddenInstallable(sourceURL)
        install(job: InstallJob(sourceURL: sourceURL, appName: nil, state: .installing("Preparing")))
    }

    func cleanup(_ item: InstallableItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            removeHiddenInstallable(item.url)
            removePendingJobs(for: item.url)
            addRecord(
                appName: item.displayName,
                sourceName: item.url.lastPathComponent,
                result: .success,
                detail: "Moved installer to Trash"
            )
            scanWatchedFolder()
        } catch {
            addRecord(
                appName: item.displayName,
                sourceName: item.url.lastPathComponent,
                result: .failed,
                detail: error.localizedDescription
            )
        }
    }

    func hide(_ item: InstallableItem) {
        guard !isInstalling(item.url) else { return }
        insertHiddenInstallable(item.url)
        removePendingJobs(for: item.url)
        scanWatchedFolder()
    }

    func unhide(_ item: InstallableItem) {
        removeHiddenInstallable(item.url)
        scanWatchedFolder()
    }

    func openApp(_ item: InstallableItem) {
        guard case .installed(let appURL, _) = item.status else { return }
        NSWorkspace.shared.open(appURL)
    }

    func simulateNotification(_ state: InstallJob.State) {
        currentJob = InstallJob(
            sourceURL: watchedFolderURL.appendingPathComponent("ExampleApp-2.4.1.dmg"),
            appName: simulatedAppName(for: state),
            state: state
        )
    }

    func dismissSimulatedNotification() {
        currentJob = nil
    }

    func populateDebugAppItems() {
        debugAppItems = AppItem.debugSamples(
            watchedFolderURL: watchedFolderURL,
            installFolderURL: installFolderURL
        )
    }

    func clearDebugAppItems() {
        debugAppItems = []
    }

    var installingItems: [InstallableItem] {
        installableItems.filter {
            if case .installing = $0.status { return true }
            return false
        }
    }

    var readyItems: [InstallableItem] {
        installableItems.filter { $0.status == .ready }
    }

    var installedItems: [InstallableItem] {
        installableItems.filter {
            if case .installed = $0.status { return true }
            return false
        }
    }

    private func install(job: InstallJob) {
        var installingJob = job
        installingJob.state = .installing("Preparing")
        installingJob.startedAt = Date()
        currentJob = installingJob
        let installDirectory = installFolderURL
        let deleteAfterInstall = DeleteAfterInstall.isEnabled
        addDiagnosticLog("Starting install for \(job.sourceURL.lastPathComponent)")
        scanWatchedFolder()

        activeInstallTask?.cancel()
        activeInstallTask = Task {
            do {
                let result = try await installWithReadinessRetries(
                    job: installingJob,
                    installDirectory: installDirectory,
                    deleteAfterInstall: deleteAfterInstall
                )
                let appName = result.appURL.deletingPathExtension().lastPathComponent
                addDiagnosticLog("Installed \(appName)")
                updateCurrentJob(appName: appName, state: .installed(appURL: result.appURL))
                addRecord(
                    appName: appName,
                    sourceName: job.sourceURL.lastPathComponent,
                    appURL: result.appURL,
                    result: .success,
                    detail: "Installed into \(installDirectory.path)"
                )
                scanWatchedFolder()
            } catch InstallServiceError.cancelled {
                addDiagnosticLog("Install cancelled for \(job.sourceURL.lastPathComponent)")
                addRecord(
                    appName: job.displayName,
                    sourceName: job.sourceURL.lastPathComponent,
                    result: .cancelled,
                    detail: "Install cancelled"
                )
                advanceToNextJob()
                scanWatchedFolder()
            } catch {
                addDiagnosticLog("Install failed for \(job.sourceURL.lastPathComponent): \(error.localizedDescription)")
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                updateCurrentJobState(.failed(notificationFailureDescription(for: error)))
                addRecord(
                    appName: job.displayName,
                    sourceName: job.sourceURL.lastPathComponent,
                    result: .failed,
                    detail: message
                )
                scanWatchedFolder()
            }

            activeInstallTask = nil
        }
    }

    private func installWithReadinessRetries(
        job: InstallJob,
        installDirectory: URL,
        deleteAfterInstall: Bool
    ) async throws -> InstallResult {
        var lastObservedSize = fileSize(for: job.sourceURL)
        var stableFailureCount = 0

        while true {
            do {
                let installer = InstallService()
                return try await installer.install(
                    sourceURL: job.sourceURL,
                    kind: job.kind,
                    installDirectory: installDirectory,
                    deleteAfterInstall: deleteAfterInstall
                ) { [weak self] message in
                    self?.updateCurrentJobState(.installing(message))
                }
            } catch {
                guard shouldRetryInstallReadinessError(error) else {
                    throw error
                }

                try checkCancellation()
                addDiagnosticLog("Install read failed for \(job.sourceURL.lastPathComponent): \(error.localizedDescription)")
                updateCurrentJobState(.installing("Installer may still be downloading. Retrying in 1s"))
                try await Task.sleep(for: .seconds(1))
                try checkCancellation()

                let currentSize = fileSize(for: job.sourceURL)
                if currentSize != lastObservedSize {
                    stableFailureCount = 0
                    addDiagnosticLog("Installer size changed; continuing retries for \(job.sourceURL.lastPathComponent)")
                    updateCurrentJobState(.installing("Download is still changing. Retrying install"))
                } else {
                    stableFailureCount += 1
                    guard stableFailureCount <= maxInstallReadinessStableRetries else {
                        addDiagnosticLog("Installer size stayed stable after retries; surfacing error for \(job.sourceURL.lastPathComponent)")
                        throw error
                    }
                }
                lastObservedSize = currentSize
            }
        }
    }

    func cancelCurrentInstall() {
        guard let job = currentJob else { return }
        if case .installing = job.state {
            activeInstallTask?.cancel()
            updateCurrentJobState(.installing("Cancelling"))
            return
        }

        addRecord(
            appName: job.displayName,
            sourceName: job.sourceURL.lastPathComponent,
            result: .cancelled,
            detail: "User declined install"
        )
        advanceToNextJob()
    }

    func dismissCurrentJob() {
        advanceToNextJob()
    }

    func openInstalledApp() {
        guard case .installed(let appURL) = currentJob?.state else { return }
        NSWorkspace.shared.open(appURL)
        advanceToNextJob()
    }

    private func handleDetectedInstallable(
        _ sourceURL: URL,
        approvalBehavior: InstallJob.ApprovalBehavior = .manual
    ) {
        guard !isHiddenInstallable(sourceURL) else { return }
        addDiagnosticLog("Queuing detected installer: \(sourceURL.lastPathComponent)")
        let job = InstallJob(
            sourceURL: sourceURL,
            appName: nil,
            state: .awaitingApproval,
            approvalBehavior: approvalBehavior
        )
        scanWatchedFolder()
        if currentJob == nil {
            currentJob = job
        } else {
            queuedJobs.append(job)
        }
    }

    private func advanceToNextJob() {
        currentJob = queuedJobs.isEmpty ? nil : queuedJobs.removeFirst()
    }

    private func removePendingJobs(for sourceURL: URL) {
        queuedJobs.removeAll { $0.sourceURL == sourceURL }

        guard currentJob?.sourceURL == sourceURL else { return }
        if case .installing = currentJob?.state {
            return
        }

        advanceToNextJob()
    }

    private func updateCurrentJobState(_ state: InstallJob.State) {
        guard var job = currentJob else { return }
        job.state = state
        currentJob = job
        scanWatchedFolder()
    }

    private func notificationFailureDescription(for error: Error) -> String {
        guard let installError = error as? InstallServiceError else {
            return "Install could not finish."
        }

        switch installError {
        case .missingFile:
            return "Installer moved or deleted."
        case .cancelled:
            return "Install cancelled."
        case .attachFailed, .archiveReadFailed, .archiveExtractFailed:
            return "Could not read the installer."
        case .noMountPoint:
            return "Could not open the disk image."
        case .noAppFound:
            return "No app was found."
        case .copyFailed:
            return "Check install folder permissions."
        case .detachFailed, .deleteFailed:
            return "Installed, but cleanup failed."
        }
    }

    private func shouldRetryInstallReadinessError(_ error: Error) -> Bool {
        guard let installError = error as? InstallServiceError else {
            return false
        }

        switch installError {
        case .attachFailed, .archiveReadFailed, .archiveExtractFailed, .noMountPoint:
            return true
        case .missingFile, .cancelled, .noAppFound, .copyFailed, .detachFailed, .deleteFailed:
            return false
        }
    }

    private func fileSize(for url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    private func checkCancellation() throws {
        if Task.isCancelled {
            throw InstallServiceError.cancelled
        }
    }

    private func updateCurrentJob(appName: String, state: InstallJob.State) {
        guard var job = currentJob else { return }
        job.appName = appName
        job.state = state
        currentJob = job
        scanWatchedFolder()
    }

    private func addRecord(appName: String, sourceName: String, appURL: URL? = nil, result: InstallRecord.Result, detail: String) {
        let record = InstallRecord(
            appName: appName,
            sourceName: sourceName,
            appURL: appURL,
            date: Date(),
            result: result,
            detail: detail
        )
        modelContext?.insert(record)
        do {
            try modelContext?.save()
        } catch {
            addDiagnosticLog("Could not save install record: \(error.localizedDescription)")
        }
        records.insert(record, at: 0)
    }

    func clearDiagnosticLog() {
        diagnosticLogEntries.removeAll()
    }

    private func addDiagnosticLog(_ message: String) {
        diagnosticLogEntries.insert(DiagnosticLogEntry(date: Date(), message: message), at: 0)
        if diagnosticLogEntries.count > 250 {
            diagnosticLogEntries.removeLast(diagnosticLogEntries.count - 250)
        }
    }

    private static func makeModelContext() -> ModelContext? {
        do {
            let container = try ModelContainer(for: InstallRecord.self)
            return ModelContext(container)
        } catch {
            return nil
        }
    }

    private static func loadRecords(from modelContext: ModelContext?) -> [InstallRecord] {
        guard let modelContext else {
            return []
        }

        do {
            var descriptor = FetchDescriptor<InstallRecord>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            descriptor.fetchLimit = 250
            return try modelContext.fetch(descriptor)
        } catch {
            return []
        }
    }

    private static func loadHiddenInstallableURLs() -> Set<URL> {
        let paths = UserDefaults.standard.stringArray(forKey: hiddenInstallablePathsKey) ?? []
        return Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL })
    }

    private func insertHiddenInstallable(_ url: URL) {
        hiddenInstallableURLs.insert(persistableURL(for: url))
        saveHiddenInstallableURLs()
    }

    private func removeHiddenInstallable(_ url: URL) {
        hiddenInstallableURLs.remove(persistableURL(for: url))
        saveHiddenInstallableURLs()
    }

    private func isHiddenInstallable(_ url: URL) -> Bool {
        hiddenInstallableURLs.contains(persistableURL(for: url))
    }

    private func saveHiddenInstallableURLs() {
        let paths = hiddenInstallableURLs.map(\.path).sorted()
        UserDefaults.standard.set(paths, forKey: Self.hiddenInstallablePathsKey)
    }

    private func persistableURL(for url: URL) -> URL {
        url.standardizedFileURL
    }

    private func scanWatchedFolder() {
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: watchedFolderURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else {
            installableItems = []
            hiddenInstallableItems = []
            return
        }

        let currentURLSet = Set(urls)
        let currentPersistableURLSet = Set(urls.map(persistableURL))
        let previousHiddenInstallableURLs = hiddenInstallableURLs
        hiddenInstallableURLs.formIntersection(currentPersistableURLSet)
        if hiddenInstallableURLs != previousHiddenInstallableURLs {
            saveHiddenInstallableURLs()
        }
        zipInstallableCache = zipInstallableCache.filter { currentURLSet.contains($0.key) }
        zipInspectionTasks.formIntersection(currentURLSet)
        zipRetryStates = zipRetryStates.filter { currentURLSet.contains($0.key) }
        appBundleSizeCache = appBundleSizeCache.filter { currentURLSet.contains($0.key) }
        appBundleSizeTasks.formIntersection(currentURLSet)

        let items: [InstallableItem] = urls
            .filter { shouldShowInstallable($0) }
            .sorted {
                let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
            .compactMap { url in
                guard let kind = InstallableKind(url: url) else { return nil }
                let metadata = metadata(for: url, kind: kind)
                return InstallableItem(
                    url: url,
                    kind: kind,
                    status: status(for: url, kind: kind),
                    metadataDate: metadata.date,
                    sizeBytes: metadata.sizeBytes
                )
            }

        installableItems = items.filter { !isHiddenInstallable($0.url) }
        hiddenInstallableItems = items.filter { isHiddenInstallable($0.url) }
    }

    private func metadata(for url: URL, kind: InstallableKind) -> (date: Date?, sizeBytes: Int64?) {
        let values = try? url.resourceValues(forKeys: [
            .addedToDirectoryDateKey,
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .totalFileSizeKey,
            .totalFileAllocatedSizeKey
        ])
        let date = metadataDate(for: url, values: values)

        guard kind == .appBundle else {
            return (date, fileSize(from: values))
        }

        if let totalSize = fileSize(from: values) {
            return (date, totalSize)
        }

        guard let fingerprint = appBundleFingerprint(for: url, values: values) else {
            return (date, nil)
        }

        if let cachedEntry = appBundleSizeCache[url], cachedEntry.fingerprint == fingerprint {
            return (date, cachedEntry.sizeBytes)
        }

        loadAppBundleSize(for: url, fingerprint: fingerprint)
        return (date, nil)
    }

    private func metadataDate(for url: URL, values: URLResourceValues?) -> Date? {
        if let date = values?.addedToDirectoryDate ?? values?.creationDate ?? values?.contentModificationDate {
            return date
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }

        return attributes[.creationDate] as? Date ?? attributes[.modificationDate] as? Date
    }

    private func fileSize(from values: URLResourceValues?) -> Int64? {
        if let totalFileSize = values?.totalFileSize {
            return Int64(totalFileSize)
        }

        if let totalFileAllocatedSize = values?.totalFileAllocatedSize {
            return Int64(totalFileAllocatedSize)
        }

        return values?.fileSize.map(Int64.init)
    }

    private func appBundleFingerprint(for url: URL, values: URLResourceValues?) -> AppBundleSizeFingerprint? {
        let contentModificationDate = values?.contentModificationDate
            ?? ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date)

        guard contentModificationDate != nil else {
            return nil
        }

        return AppBundleSizeFingerprint(contentModificationDate: contentModificationDate)
    }

    private func loadAppBundleSize(for url: URL, fingerprint: AppBundleSizeFingerprint) {
        guard !appBundleSizeTasks.contains(url) else { return }
        appBundleSizeTasks.insert(url)

        Task { [weak self] in
            let result: Result<Int64, Error>
            do {
                let shellResult = try await Shell.run("/usr/bin/du", arguments: ["-sk", url.path])
                if shellResult.status == 0,
                   let kilobytesText = shellResult.output.split(whereSeparator: \.isWhitespace).first,
                   let kilobytes = Int64(kilobytesText) {
                    result = .success(kilobytes * 1024)
                } else {
                    result = .failure(NSError(
                        domain: "Poppy.AppBundleSize",
                        code: Int(shellResult.status),
                        userInfo: [NSLocalizedDescriptionKey: shellResult.error]
                    ))
                }
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                guard let self else { return }
                self.appBundleSizeTasks.remove(url)

                guard self.appBundleFingerprint(for: url, values: nil) == fingerprint else {
                    self.appBundleSizeCache.removeValue(forKey: url)
                    self.scanWatchedFolder()
                    return
                }

                switch result {
                case .success(let sizeBytes):
                    self.appBundleSizeCache[url] = AppBundleSizeCacheEntry(
                        fingerprint: fingerprint,
                        sizeBytes: sizeBytes
                    )
                    self.scanWatchedFolder()
                case .failure(let error):
                    self.addDiagnosticLog("App bundle size lookup failed for \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
    }

    private func shouldShowInstallable(_ url: URL) -> Bool {
        guard let kind = InstallableKind(url: url) else { return false }
        guard kind == .zipArchive else { return true }

        guard let fingerprint = zipFingerprint(for: url) else {
            return false
        }

        if let cachedEntry = zipInstallableCache[url], cachedEntry.fingerprint == fingerprint {
            return cachedEntry.containsApp
        }

        inspectZipForList(url, fingerprint: fingerprint)
        return false
    }

    private func inspectZipForList(_ url: URL, fingerprint: ZipFileFingerprint) {
        guard !zipInspectionTasks.contains(url) else { return }
        zipInspectionTasks.insert(url)

        Task { [weak self] in
            let result: Result<String?, Error>
            do {
                result = .success(try await ZipArchiveInspector.findAppEntry(in: url))
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                guard let self else { return }
                self.zipInspectionTasks.remove(url)

                guard self.zipFingerprint(for: url) == fingerprint else {
                    self.zipInstallableCache.removeValue(forKey: url)
                    self.zipRetryStates.removeValue(forKey: url)
                    self.scanWatchedFolder()
                    return
                }

                switch result {
                case .success(let appEntry):
                    self.zipRetryStates.removeValue(forKey: url)
                    self.addDiagnosticLog(
                        appEntry == nil
                            ? "List zip ignored because no app was found: \(url.lastPathComponent)"
                            : "List zip contains an app: \(url.lastPathComponent)"
                    )
                    self.zipInstallableCache[url] = ZipInstallableCacheEntry(
                        fingerprint: fingerprint,
                        containsApp: appEntry != nil
                    )
                    self.scanWatchedFolder()
                case .failure:
                    self.addDiagnosticLog("List zip inspection failed for \(url.lastPathComponent)")
                    self.scheduleZipListInspectionRetry(for: url, fingerprint: fingerprint)
                }
            }
        }
    }

    private func scheduleZipListInspectionRetry(for url: URL, fingerprint: ZipFileFingerprint) {
        let currentSize = fileSize(for: url)
        let state = zipRetryStates[url] ?? ZipRetryState(lastObservedSize: currentSize, stableFailureCount: 0)
        let nextStableFailureCount = state.lastObservedSize == currentSize ? state.stableFailureCount + 1 : 0

        guard nextStableFailureCount <= maxInstallReadinessStableRetries else {
            zipRetryStates.removeValue(forKey: url)
            zipInstallableCache[url] = ZipInstallableCacheEntry(fingerprint: fingerprint, containsApp: false)
            addDiagnosticLog("List zip inspection stopped after stable failures: \(url.lastPathComponent)")
            scanWatchedFolder()
            return
        }

        zipRetryStates[url] = ZipRetryState(
            lastObservedSize: currentSize,
            stableFailureCount: nextStableFailureCount
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            guard self.zipFingerprint(for: url) == fingerprint else {
                self.zipInstallableCache.removeValue(forKey: url)
                self.zipRetryStates.removeValue(forKey: url)
                self.scanWatchedFolder()
                return
            }
            self.addDiagnosticLog("Retrying list zip inspection: \(url.lastPathComponent)")
            self.inspectZipForList(url, fingerprint: fingerprint)
        }
    }

    private func zipFingerprint(for url: URL) -> ZipFileFingerprint? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return nil
        }
        return ZipFileFingerprint(
            contentModificationDate: values.contentModificationDate,
            fileSize: values.fileSize
        )
    }

    private func status(for sourceURL: URL, kind: InstallableKind) -> InstallableItem.Status {
        if let installingStatus = installingStatus(for: sourceURL) {
            return installingStatus
        }

        if let installedAppURL = installedAppURL(for: sourceURL, kind: kind) {
            return .installed(appURL: installedAppURL, installedAt: installedDate(for: sourceURL))
        }

        return .ready
    }

    private func installingStatus(for sourceURL: URL) -> InstallableItem.Status? {
        guard currentJob?.sourceURL == sourceURL else { return nil }

        switch currentJob?.state {
        case .installing(let step):
            return .installing(step, startedAt: currentJob?.startedAt)
        case .some(.installed(let appURL)):
            return .installed(appURL: appURL, installedAt: installedDate(for: sourceURL))
        default:
            return nil
        }
    }

    private func isInstalling(_ sourceURL: URL) -> Bool {
        guard currentJob?.sourceURL == sourceURL else { return false }
        if case .installing = currentJob?.state {
            return true
        }
        return false
    }

    private func installedAppURL(for sourceURL: URL, kind: InstallableKind) -> URL? {
        for name in appNameCandidates(for: sourceURL, kind: kind) {
            let appURL = installFolderURL.appendingPathComponent(name).appendingPathExtension("app")
            if FileManager.default.fileExists(atPath: appURL.path) {
                return appURL
            }
        }
        return nil
    }

    private func installedDate(for sourceURL: URL) -> Date? {
        records.first {
            $0.result == .success && $0.sourceName == sourceURL.lastPathComponent
        }?.date
    }

    private func appNameCandidates(for sourceURL: URL, kind: InstallableKind) -> [String] {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var candidates = [baseName]

        if kind == .appBundle {
            return candidates
        }

        if let range = baseName.range(of: #"[-_ ]\d"#, options: .regularExpression) {
            let prefix = String(baseName[..<range.lowerBound])
            if !prefix.isEmpty {
                candidates.append(prefix)
            }
        }

        return Array(Set(candidates))
    }

    private func simulatedAppName(for state: InstallJob.State) -> String? {
        switch state {
        case .installed:
            "ExampleApp"
        default:
            nil
        }
    }
}

private struct ZipFileFingerprint: Equatable {
    let contentModificationDate: Date?
    let fileSize: Int?
}

private struct ZipInstallableCacheEntry {
    let fingerprint: ZipFileFingerprint
    let containsApp: Bool
}

private struct AppBundleSizeFingerprint: Equatable {
    let contentModificationDate: Date?
}

private struct AppBundleSizeCacheEntry {
    let fingerprint: AppBundleSizeFingerprint
    let sizeBytes: Int64
}

private struct ZipRetryState {
    let lastObservedSize: Int?
    let stableFailureCount: Int
}
