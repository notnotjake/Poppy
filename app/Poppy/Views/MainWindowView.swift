import AppKit
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var store: InstallStore
    let openSettings: () -> Void
    @AppStorage(HiddenItemsVisibility.storageKey) private var showsHiddenItems = false
    @State private var isHoveringHiddenToggle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 24) {
                    availableSection

                    if !installedAppItems.isEmpty {
                        appItemSection(
                            title: "Installed",
                            items: installedAppItems,
                            emptyTitle: "No installed apps to delete",
                            emptySystemImage: "checkmark.circle"
                        )
                    }

                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.clear)
    }

    private var installingAppItems: [AppItem] {
        (store.installingItems.map { AppItem(installableItem: $0) } + debugItems { $0.isInstalling })
            .sorted {
                ($0.installStartedDate ?? .distantFuture) < ($1.installStartedDate ?? .distantFuture)
            }
    }

    private var readyAppItems: [AppItem] {
        sortNewestFirst(store.readyItems.map { AppItem(installableItem: $0) } + debugItems { $0.isReady })
    }

    private var availableAppItems: [AppItem] {
        installingAppItems + readyAppItems
    }

    private var installedAppItems: [AppItem] {
        let watchedFolderInstalledItems = store.installedItems.map { AppItem(installableItem: $0) }
        let watchedFolderInstalledSourceNames = Set(watchedFolderInstalledItems.map(\.fileName))
        let recordInstalledItems = store.records
            .filter { $0.result == .success && $0.appURL != nil && !watchedFolderInstalledSourceNames.contains($0.sourceName) }
            .map { AppItem(installRecord: $0) }

        return sortNewestFirst(watchedFolderInstalledItems + recordInstalledItems + debugItems { $0.isInstalled })
    }

    private var hiddenAppItems: [AppItem] {
        sortNewestFirst(store.hiddenInstallableItems.map { AppItem(installableItem: $0, isHidden: true) } + debugItems { $0.isHidden })
    }

    private func debugItems(matching predicate: (AppItem.State) -> Bool) -> [AppItem] {
        store.debugAppItems.filter { predicate($0.state) }
    }

    private func sortNewestFirst(_ items: [AppItem]) -> [AppItem] {
        items.sorted {
            ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            watchToggleButton

            LocationRouteButton(
                watchedFolderURL: store.watchedFolderURL,
                installFolderURL: store.installFolderURL,
                isWatching: store.isWatching,
                chooseDownloads: {
                    store.chooseWatchedFolder()
                },
                resetDownloads: {
                    store.resetWatchedFolder()
                },
                openDownloads: {
                    store.openWatchedFolder()
                },
                chooseInstall: {
                    store.chooseInstallFolder()
                },
                resetInstall: {
                    store.resetInstallFolder()
                },
                openInstall: {
                    store.openInstallFolder()
                }
            )

            settingsButton
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var watchToggleButton: some View {
        circularToolbarButton(
            systemImage: store.isWatching ? "pause.fill" : "play.fill",
            accessibilityLabel: store.isWatching ? "Pause watching" : "Start watching",
            help: "Pause Watching Downloads"
        ) {
            store.isWatching ? store.stop() : store.start()
        }
    }

    private var settingsButton: some View {
        circularToolbarButton(
            systemImage: "gearshape.fill",
            accessibilityLabel: "Open Settings",
            help: "Open Settings"
        ) {
            openSettings()
        }
    }

    @ViewBuilder
    private func circularToolbarButton(
        systemImage: String,
        accessibilityLabel: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            circleGlassIcon(systemImage: systemImage)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(help)
    }

    @ViewBuilder
    private func circleGlassIcon(systemImage: String) -> some View {
        if #available(macOS 26.0, *) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .background(.regularMaterial, in: Circle())
        }
    }

    private func appItemSection(
        title: String,
        items: [AppItem],
        emptyTitle: String,
        emptySystemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            appItemSectionHeader(title: title, items: items)

            if items.isEmpty {
                Label(emptyTitle, systemImage: emptySystemImage)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        AppItemElement(item: item, showsSeparator: index < items.count - 1, actions: {
                            controls(for: item)
                        }, contextMenuActions: {
                            contextMenuActions(for: item)
                        })
                    }
                }
            }
        }
    }

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            appItemSectionHeader(
                title: "Available",
                items: availableAppItems,
                showsHiddenToggle: true
            )

            if availableAppItems.isEmpty {
                AvailableAppsEmptyState()
            }

            if !availableAppItems.isEmpty || (showsHiddenItems && !hiddenAppItems.isEmpty) {
                VStack(spacing: 0) {
                    ForEach(Array(availableAppItems.enumerated()), id: \.element.id) { index, item in
                        AppItemElement(item: item, showsSeparator: showsAvailableSeparator(after: index), actions: {
                            controls(for: item)
                        }, contextMenuActions: {
                            contextMenuActions(for: item)
                        })
                    }

                    if showsHiddenItems && !hiddenAppItems.isEmpty {
                        hiddenSubheading

                        ForEach(Array(hiddenAppItems.enumerated()), id: \.element.id) { index, item in
                            AppItemElement(item: item, showsSeparator: index < hiddenAppItems.count - 1, actions: {
                                controls(for: item)
                            }, contextMenuActions: {
                                contextMenuActions(for: item)
                            })
                        }
                    }
                }
            }
        }
    }

    private func showsAvailableSeparator(after index: Int) -> Bool {
        index < availableAppItems.count - 1
    }

    private var hiddenSubheading: some View {
        HStack(spacing: 8) {
            Text("Hidden")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text(itemCountText(for: hiddenAppItems.count))

                Rectangle()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 1, height: 11)

                Text(totalSizeText(for: hiddenAppItems))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.secondary.opacity(0.08), in: Capsule())

            Spacer()

            Button("Hide Hidden") {
                showsHiddenItems = false
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .help("Hide Hidden Items")
        }
        .padding(.top, availableAppItems.isEmpty ? 0 : 10)
        .padding(.bottom, 4)
    }

    private func appItemSectionHeader(title: String, items: [AppItem], showsHiddenToggle: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.title2.weight(.semibold))

            HStack(spacing: 6) {
                Text(itemCountText(for: items.count))

                Rectangle()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 1, height: 11)

                Text(totalSizeText(for: items))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.secondary.opacity(0.08), in: Capsule())

            Spacer()

            if showsHiddenToggle {
                hiddenToggleButton
            }
        }
    }

    private var hiddenToggleButton: some View {
        HStack(spacing: 6) {
            Text(showsHiddenItems ? "Hide Hidden" : "Show Hidden")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .opacity(isHoveringHiddenToggle ? 1 : 0)
                .animation(.easeOut(duration: 0.16), value: isHoveringHiddenToggle)

            Button {
                showsHiddenItems.toggle()
            } label: {
                Image(systemName: showsHiddenItems ? "eye.slash" : "eye")
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showsHiddenItems ? "Hide Hidden Items" : "Show Hidden Items")
            .accessibilityLabel(showsHiddenItems ? "Hide hidden items" : "Show hidden items")
        }
        .onHover { isHoveringHiddenToggle = $0 }
    }

    private func itemCountText(for count: Int) -> String {
        count == 1 ? "1 Item" : "\(count) Items"
    }

    private func totalSizeText(for items: [AppItem]) -> String {
        let totalSize = items.compactMap(\.sizeBytes).reduce(Int64(0), +)
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
            .replacingOccurrences(of: " ", with: "")
    }

    @ViewBuilder
    private func controls(for item: AppItem) -> some View {
        switch item.state {
        case .ready:
            moreMenu(for: item)
            installButton(for: item)
        case .hidden:
            moreMenu(for: item)
        case .installing:
            InstallingSpinner(size: 30)
        case .installedCleanedUp:
            openButton(for: item)
        case .installedNeedsCleanup:
            cleanupIconButton(for: item)
            openButton(for: item)
        }
    }

    private func installButton(for item: AppItem) -> some View {
        Button {
            if let installableItem = installableItem(for: item) {
                store.installNow(installableItem)
            }
        } label: {
            primaryCapsuleActionLabel("Install", systemImage: "arrow.down")
        }
        .buttonStyle(.plain)
        .disabled(installableItem(for: item) == nil)
        .opacity(installableItem(for: item) == nil ? 0.5 : 1)
    }

    private func cleanupButton(for item: AppItem) -> some View {
        Button(role: .destructive) {
            if let installableItem = installableItem(for: item) {
                store.cleanup(installableItem)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(installableItem(for: item) == nil)
    }

    private func cleanupIconButton(for item: AppItem) -> some View {
        Button {
            if let installableItem = installableItem(for: item) {
                store.cleanup(installableItem)
            }
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .disabled(installableItem(for: item) == nil)
        .opacity(installableItem(for: item) == nil ? 0.5 : 1)
    }

    private func openButton(for item: AppItem) -> some View {
        Button {
            if let appURL = item.appURL {
                NSWorkspace.shared.open(appURL)
            } else if let installableItem = installableItem(for: item) {
                store.openApp(installableItem)
            }
        } label: {
            primaryCapsuleActionLabel("Open")
        }
        .buttonStyle(.plain)
        .disabled(item.appURL == nil && installableItem(for: item) == nil)
        .opacity(item.appURL == nil && installableItem(for: item) == nil ? 0.5 : 1)
    }

    private func primaryCapsuleActionLabel(_ title: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }

            Text(title)
        }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.leading, systemImage == nil ? 12 : 9)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor, in: Capsule())
    }

    private func moreMenu(for item: AppItem) -> some View {
        Menu {
            secondaryMenuActions(for: item)
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 21, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func contextMenuActions(for item: AppItem) -> some View {
        switch item.state {
        case .installedCleanedUp, .installedNeedsCleanup:
            openMenuAction(for: item)
        case .ready:
            installMenuAction(for: item)
        case .hidden, .installing:
            EmptyView()
        }

        if item.state.hasPrimaryContextAction {
            Divider()
        }

        secondaryMenuActions(for: item)
    }

    @ViewBuilder
    private func secondaryMenuActions(for item: AppItem) -> some View {
        if item.state.isHidden {
            showMenuAction(for: item)
        } else if item.state.canHide {
            hideMenuAction(for: item)
        }

        if item.revealURL != nil {
            revealInFinderMenuAction(for: item)
        }

        if item.state.canCleanup {
            cleanupMenuAction(for: item)
        }
    }

    private func installMenuAction(for item: AppItem) -> some View {
        Button {
            if let installableItem = installableItem(for: item) {
                store.installNow(installableItem)
            }
        } label: {
            Label("Install", systemImage: "arrow.down")
        }
        .disabled(installableItem(for: item) == nil)
    }

    private func cleanupMenuAction(for item: AppItem) -> some View {
        Button(role: .destructive) {
            if let installableItem = installableItem(for: item) {
                store.cleanup(installableItem)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(installableItem(for: item) == nil)
    }

    private func openMenuAction(for item: AppItem) -> some View {
        Button {
            if let appURL = item.appURL {
                NSWorkspace.shared.open(appURL)
            } else if let installableItem = installableItem(for: item) {
                store.openApp(installableItem)
            }
        } label: {
            Label("Open", systemImage: "arrow.up.right.square")
        }
        .disabled(item.appURL == nil && installableItem(for: item) == nil)
    }

    private func hideMenuAction(for item: AppItem) -> some View {
        Button {
            if let installableItem = installableItem(for: item) {
                store.hide(installableItem)
            }
        } label: {
            Label("Hide", systemImage: "eye.slash")
        }
        .disabled(installableItem(for: item) == nil)
    }

    private func showMenuAction(for item: AppItem) -> some View {
        Button {
            if let installableItem = installableItem(for: item) {
                store.unhide(installableItem)
            }
        } label: {
            Label("Unhide", systemImage: "eye")
        }
        .disabled(installableItem(for: item) == nil)
    }

    private func revealInFinderMenuAction(for item: AppItem) -> some View {
        Button {
            if let revealURL = item.revealURL {
                NSWorkspace.shared.activateFileViewerSelecting([revealURL])
            }
        } label: {
            Label("Show in Finder", systemImage: "finder")
        }
    }

    private func installableItem(for appItem: AppItem) -> InstallableItem? {
        (store.installableItems + store.hiddenInstallableItems).first { $0.id == appItem.id }
    }
}

private struct AvailableAppsEmptyState: View {
    var body: some View {
        VStack(spacing: 4) {
            AppIconStackEmptyStateGraphic()

            Text("Apps you download will show up here")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}

private struct AppIconStackEmptyStateGraphic: View {
    private let iconSize: CGFloat = 74
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        iconGroup
            .frame(width: 240, height: 94)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.48),
                        .init(color: .clear, location: 0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var iconGroup: some View {
        ZStack {
            emptyIcon(offsetX: -63, offsetY: 17, rotation: -10, opacity: 0.46, lineOpacity: 0.34)
                .zIndex(0)

            emptyIcon(offsetX: 63, offsetY: 17, rotation: 10, opacity: 0.46, lineOpacity: 0.34)
                .zIndex(0)

            frontIcon
                .zIndex(1)
        }
    }

    private func emptyIcon(
        offsetX: CGFloat,
        offsetY: CGFloat,
        rotation: Double,
        opacity: Double,
        lineOpacity: Double
    ) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.secondary.opacity(0.16),
                        Color.secondary.opacity(0.05)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.secondary.opacity(lineOpacity), lineWidth: 3)
            }
            .frame(width: iconSize, height: iconSize)
            .opacity(opacity)
            .rotationEffect(.degrees(rotation))
            .offset(x: offsetX, y: offsetY)
    }

    private var frontIcon: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(frontBaseFill)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.secondary.opacity(frontFillTopOpacity),
                                Color.secondary.opacity(frontFillBottomOpacity)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.orange.opacity(orangeGlowCoreOpacity),
                                Color.orange.opacity(orangeGlowFalloffOpacity),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.76, y: 0.22),
                            startRadius: 2,
                            endRadius: 56
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.secondary.opacity(0.56), lineWidth: 3)
            }
            .frame(width: iconSize, height: iconSize)
            .opacity(0.84)
    }

    private var frontBaseFill: Color {
        if colorScheme == .light {
            return Color(nsColor: .windowBackgroundColor).opacity(0.4)
        }

        return Color(nsColor: .windowBackgroundColor).opacity(0.82)
    }

    private var frontFillTopOpacity: Double {
        colorScheme == .light ? 0.08 : 0.18
    }

    private var frontFillBottomOpacity: Double {
        colorScheme == .light ? 0.02 : 0.06
    }

    private var orangeGlowCoreOpacity: Double {
        colorScheme == .light ? 0.3 : 0.20
    }

    private var orangeGlowFalloffOpacity: Double {
        colorScheme == .light ? 0.05 : 0.06
    }
}

private struct LocationRouteButton: View {
    private static let segmentWidth: CGFloat = 178

    let watchedFolderURL: URL
    let installFolderURL: URL
    let isWatching: Bool
    let chooseDownloads: () -> Void
    let resetDownloads: () -> Void
    let openDownloads: () -> Void
    let chooseInstall: () -> Void
    let resetInstall: () -> Void
    let openInstall: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        label
    }

    @ViewBuilder
    private var label: some View {
        if #available(macOS 26.0, *) {
            content
                .frame(height: 42)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .frame(height: 42)
                .background(.regularMaterial, in: Capsule())
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            locationSegment(
                title: "Watching",
                systemImage: "arrow.down.circle.fill",
                defaultName: "Downloads",
                url: watchedFolderURL,
                defaultURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true),
                iconPlacement: .leading,
                action: chooseDownloads,
                reset: resetDownloads,
                open: openDownloads
            )

            ZStack {
                Rectangle()
                    .fill(.primary.opacity(0.12))
                    .frame(width: 1)

                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 24, height: 24)
                    .background(arrowBackground, in: Circle())
                    .compositingGroup()
                    .zIndex(1)
            }
            .frame(width: 28, height: 42)

            locationSegment(
                title: "Install To",
                systemImage: "circle.grid.3x3.circle.fill",
                defaultName: "Applications",
                url: installFolderURL,
                defaultURL: URL(fileURLWithPath: "/Applications", isDirectory: true),
                iconPlacement: .trailing,
                action: chooseInstall,
                reset: resetInstall,
                open: openInstall
            )
        }
        .foregroundStyle(.primary)
    }

    private var arrowBackground: Color {
        isWatching ? .accentColor : .secondary.opacity(0.42)
    }

    private func locationSegment(
        title: String,
        systemImage: String,
        defaultName: String,
        url: URL,
        defaultURL: URL,
        iconPlacement: LocationIconPlacement,
        action: @escaping () -> Void,
        reset: @escaping () -> Void,
        open: @escaping () -> Void
    ) -> some View {
        LocationSegmentButton(
            title: title,
            systemImage: systemImage,
            defaultName: defaultName,
            url: url,
            defaultURL: defaultURL,
            iconPlacement: iconPlacement,
            action: action,
            reset: reset,
            open: open
        )
        .frame(width: Self.segmentWidth, height: 42)
    }

}

private enum LocationIconPlacement {
    case leading
    case trailing
}

private struct LocationSegmentButton: View {
    let title: String
    let systemImage: String
    let defaultName: String
    let url: URL
    let defaultURL: URL
    let iconPlacement: LocationIconPlacement
    let action: () -> Void
    let reset: () -> Void
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            if iconPlacement == .leading {
                segmentIcon

                segmentButton
            } else {
                segmentButton
            }

            if isHovered {
                hoverButtons
            }

            if iconPlacement == .trailing {
                segmentIcon
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, iconPlacement == .leading ? 12 : 14)
        .padding(.trailing, iconPlacement == .trailing ? 12 : 14)
        .onHover { isHovered = $0 }
    }

    private var segmentButton: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                if isHovered {
                    Text("Choose...")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    locationDetail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var segmentIcon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.primary)
            .frame(width: 22)
    }

    private var hoverButtons: some View {
        HStack(spacing: 5) {
            utilityButton(systemImage: "arrow.counterclockwise", action: reset, help: "Reset to Default Location")
            utilityButton(systemImage: "finder", action: open, help: "Open in Finder")
        }
    }

    private func utilityButton(systemImage: String, action: @escaping () -> Void, help: String) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var locationDetail: some View {
        if url.standardizedFileURL == defaultURL.standardizedFileURL {
            (Text("Default ")
                .fontWeight(.semibold)
             + Text(defaultName)
                .fontWeight(.regular))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(shortPath(for: url))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    private func shortPath(for url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)

        if path.hasPrefix(homePath) {
            return "~" + path.dropFirst(homePath.count)
        }

        return path
    }
}

private struct AppItemElement<Actions: View, ContextMenuActions: View>: View {
    let item: AppItem
    let showsSeparator: Bool
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var contextMenuActions: () -> ContextMenuActions

    var body: some View {
        listLayout
    }

    private var listLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                listContextRegion

                HStack(spacing: 8) {
                    actions()
                }
            }
            .padding(.vertical, 8)
            .background(alignment: .center) {
                if item.state.isInstalling {
                    InstallingRowGlow()
                }
            }

            if showsSeparator {
                Rectangle()
                    .fill(.separator.opacity(0.55))
                    .frame(height: 1)
                    .padding(.leading, listSeparatorLeadingPadding)
            }
        }
    }

    private var listSeparatorLeadingPadding: CGFloat {
        44
    }

    private var listContextRegion: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 32, height: 32)

            itemText(spacing: 2)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            contextMenuActions()
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.state {
        case .installedCleanedUp(let appURL):
            if let appURL {
                appIcon(for: appURL)
            } else {
                fallbackIcon(systemName: "app.dashed", color: .secondary)
            }
        case .installedNeedsCleanup(let appURL):
            appIcon(for: appURL)
        case .ready:
            fileIcon
        case .installing:
            fileIcon
                .opacity(0.7)
        case .hidden:
            fileIcon
                .opacity(0.42)
        }
    }

    private var fileIcon: some View {
        Group {
            if let fileURL = item.fileURL {
                appIcon(for: fileURL)
            } else {
                fallbackIcon(systemName: item.kind.systemImage, color: .secondary)
            }
        }
    }

    private func appIcon(for url: URL) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .scaledToFit()
    }

    private func fallbackIcon(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .padding(3)
    }

    private func itemText(spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(spacing: 5) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)

                if item.isDebugSample {
                    Text("Sample")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            metadataLine
        }
    }

    @ViewBuilder
    private var metadataLine: some View {
        if item.createdDate != nil || item.sizeBytes != nil {
            HStack(spacing: 6) {
                metadataContent(dateFontSize: 12, sizeFontSize: 12)
            }
            .lineLimit(1)
        } else {
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private func metadataContent(dateFontSize: CGFloat, sizeFontSize: CGFloat) -> some View {
        if let createdDate = item.createdDate {
            Text(Self.metadataDateText(for: createdDate))
                .font(.system(size: dateFontSize, weight: .regular))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }

        if let sizeBytes = item.sizeBytes {
            Text(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
                .font(.system(size: sizeFontSize, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var detail: String {
        switch item.state {
        case .hidden:
            return "\(item.fileName) - Hidden from install prompts"
        case .ready:
            return item.fileName
        case .installing(let step):
            return "\(item.fileName) - \(step)"
        case .installedCleanedUp(let appURL):
            return appURL?.lastPathComponent ?? item.name
        case .installedNeedsCleanup:
            return "Installer Left \(item.fileName.truncatedTail(to: 25))"
        }
    }

    private static func metadataDateText(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }

        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct InstallingRowGlow: View {
    var body: some View {
        Color.accentColor
            .opacity(0.14)
        .blur(radius: 10)
        .padding(.horizontal, -20)
        .padding(.vertical, -3)
        .allowsHitTesting(false)
    }
}

private struct InstallingSpinner: View {
    let size: CGFloat
    @State private var rotation = Angle.degrees(0)

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.88)
                .stroke(
                    Color.secondary,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .frame(width: 18, height: 18)
                .rotationEffect(rotation)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                rotation = .degrees(360)
            }
        }
    }
}

private extension AppItem.State {
    var isHidden: Bool {
        if case .hidden = self { return true }
        return false
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isInstalling: Bool {
        if case .installing = self { return true }
        return false
    }

    var isInstalled: Bool {
        switch self {
        case .installedCleanedUp, .installedNeedsCleanup:
            return true
        case .hidden, .ready, .installing:
            return false
        }
    }

    var canCleanup: Bool {
        switch self {
        case .hidden, .ready, .installedNeedsCleanup:
            return true
        case .installing, .installedCleanedUp:
            return false
        }
    }

    var canHide: Bool {
        switch self {
        case .ready:
            return true
        case .hidden, .installing, .installedCleanedUp, .installedNeedsCleanup:
            return false
        }
    }

    var hasPrimaryContextAction: Bool {
        switch self {
        case .ready, .installedCleanedUp, .installedNeedsCleanup:
            return true
        case .hidden, .installing:
            return false
        }
    }
}

private extension AppItem {
    var revealURL: URL? {
        fileURL ?? appURL
    }
}

private extension String {
    func truncatedTail(to maxLength: Int) -> String {
        guard count > maxLength else { return self }
        guard maxLength > 3 else { return String(prefix(maxLength)) }
        return String(prefix(maxLength - 3)) + "..."
    }
}

private extension InstallableKind {
    var systemImage: String {
        switch self {
        case .diskImage:
            return "externaldrive"
        case .appBundle:
            return "app"
        case .zipArchive:
            return "doc.zipper"
        }
    }
}
