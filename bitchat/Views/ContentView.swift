//
// ContentView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
import CoreLocation
import MapKit
import BitFoundation
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif
import UniformTypeIdentifiers
import BitLogger
import BitFoundation

/// On macOS 14+, disables the default system focus ring on TextFields.
/// On earlier macOS versions and on iOS this is a no-op.
private struct FocusEffectDisabledModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 14.0, *) {
            content.focusEffectDisabled()
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Main Content View

struct ContentView: View {
    // MARK: - Properties
    
    @EnvironmentObject var viewModel: ChatViewModel
    @StateObject private var voiceRecordingVM = VoiceRecordingViewModel()
    @ObservedObject private var locationManager = LocationChannelManager.shared
    @ObservedObject private var bookmarks = GeohashBookmarksStore.shared
    @State private var messageText = ""
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showSidebar = false
    @State private var showAppInfo = false
    @State private var showSettings = false
    @State private var showComposerActions = false
    @State private var showSOSConfirm = false
    @State private var showSOSMapSheet = false
    @State private var showRadarSheet = false
    @State private var showSideDrawer = false
    @State private var showChannelMore = false
    @State private var showChannelManager = false
    @State private var channelMuted = false
    @State private var selectedTopic: String = "global"
    @State private var managedChannels: [ManagedChannel] = ManagedChannel.defaults
    @AppStorage("meshcomm.channels.v2") private var managedChannelsBlob: String = ""
    @AppStorage("meshcomm.sos.lastSeenID") private var lastSeenSOSID: String = ""
    @AppStorage("meshcomm.themePreference") private var themePreference: String = "system"
    @StateObject private var composerSOSLocator = SOSLocationFetcher()
    @State private var selectedMessageSender: String?
    @State private var selectedMessageSenderID: PeerID?
    @FocusState private var isNicknameFieldFocused: Bool
    @State private var isAtBottomPublic: Bool = true
    @State private var isAtBottomPrivate: Bool = true
    @State private var autocompleteDebounceTimer: Timer?
    @State private var showLocationChannelsSheet = false
    @State private var showVerifySheet = false
    @State private var showLocationNotes = false
    @State private var notesGeohash: String? = nil
    @State private var imagePreviewURL: URL? = nil
#if os(iOS)
    @State private var showImagePicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .camera
#else
    @State private var showMacImagePicker = false
#endif
    @ScaledMetric(relativeTo: .body) private var headerHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var headerPeerIconSize: CGFloat = 11
    @ScaledMetric(relativeTo: .subheadline) private var headerPeerCountFontSize: CGFloat = 12
    // Timer-based refresh removed; use LocationChannelManager live updates instead
    // Window sizes for rendering (infinite scroll up)
    @State private var windowCountPublic: Int = 300
    @State private var windowCountPrivate: [PeerID: Int] = [:]
    
    // MARK: - Computed Properties
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var textColor: Color {
        colorScheme == .dark ? Color(red: 0.851, green: 0.467, blue: 0.341) : Color(red: 0.722, green: 0.351, blue: 0.231)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color(red: 0.851, green: 0.467, blue: 0.341).opacity(0.8) : Color(red: 0.722, green: 0.351, blue: 0.231).opacity(0.8)
    }

    private var headerLineLimit: Int? {
        dynamicTypeSize.isAccessibilitySize ? 2 : 1
    }

    private var peopleSheetTitle: String {
        String(localized: "content.header.people", comment: "Title for the people list sheet").lowercased()
    }

    private var peopleSheetSubtitle: String? {
        switch locationManager.selectedChannel {
        case .mesh:
            return "#mesh"
        case .location(let channel):
            return "#\(channel.geohash.lowercased())"
        }
    }

    private var peopleSheetActiveCount: Int {
        switch locationManager.selectedChannel {
        case .mesh:
            return viewModel.allPeers.filter { $0.peerID != viewModel.meshService.myPeerID }.count
        case .location:
            return viewModel.visibleGeohashPeople().count
        }
    }
    
    
    private struct PrivateHeaderContext {
        let headerPeerID: PeerID
        let peer: BitchatPeer?
        let displayName: String
        let isNostrAvailable: Bool
    }

// MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            mainHeaderView
                .onAppear {
                    viewModel.currentColorScheme = colorScheme
                    #if os(macOS)
                    // Focus message input on macOS launch, not nickname field
                    DispatchQueue.main.async {
                        isNicknameFieldFocused = false
                        isTextFieldFocused = true
                    }
                    #endif
                }
                .onChange(of: colorScheme) { newValue in
                    viewModel.currentColorScheme = newValue
                }

            statusStripView

            GeometryReader { geometry in
                VStack(spacing: 0) {
                    MessageListView(
                        privatePeer: nil,
                        isAtBottom: $isAtBottomPublic,
                        messageText: $messageText,
                        selectedMessageSender: $selectedMessageSender,
                        selectedMessageSenderID: $selectedMessageSenderID,
                        imagePreviewURL: $imagePreviewURL,
                        windowCountPublic: $windowCountPublic,
                        windowCountPrivate: $windowCountPrivate,
                        showSidebar: $showSidebar,
                        isTextFieldFocused: $isTextFieldFocused,
                    )
                    .background(backgroundColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }

            Divider()

            if viewModel.selectedPrivateChatPeer == nil {
                inputView
            }
        }
        .background(backgroundColor)
        .foregroundColor(textColor)
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 400)
        #endif
        .onChange(of: viewModel.selectedPrivateChatPeer) { newValue in
            if newValue != nil {
                showSidebar = true
            }
        }
        .sheet(
            isPresented: Binding(
                get: { showSidebar || viewModel.selectedPrivateChatPeer != nil },
                set: { isPresented in
                    if !isPresented {
                        showSidebar = false
                        viewModel.endPrivateChat()
                    }
                }
            )
        ) {
            peopleSheetView
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showAppInfo) {
            AppInfoView()
                .environmentObject(viewModel)
                .onAppear { viewModel.isAppInfoPresented = true }
                .onDisappear { viewModel.isAppInfoPresented = false }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showSOSMapSheet, onDismiss: markIncomingSOSAsSeen) {
            SOSMapView(pins: viewModel.sosPins)
                .onAppear { markIncomingSOSAsSeen() }
        }
        .sheet(isPresented: $showRadarSheet) {
            RadarSheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $showChannelMore) { channelMoreSheet }
        .sheet(isPresented: $showChannelManager) {
            ChannelManagerSheet(
                channels: $managedChannels,
                selectedTopic: $selectedTopic
            )
        }
        .overlay { sideDrawerScrim }
        .overlay(alignment: .topLeading) { sideDrawerOverlay }
        .animation(.easeInOut(duration: 0.24), value: showSideDrawer)
        .preferredColorScheme(themeColorScheme)
        .onAppear(perform: loadManagedChannels)
        .onChange(of: managedChannels) { _ in persistManagedChannels() }
        .confirmationDialog(
            "Inviare SOS broadcast?",
            isPresented: $showSOSConfirm,
            titleVisibility: .visible
        ) {
            Button("Invia SOS", role: .destructive) {
                Task { @MainActor in
                    let coord = await composerSOSLocator.fetchOnce()
                    viewModel.sendSOSMessage(
                        latitude: coord?.latitude,
                        longitude: coord?.longitude
                    )
                }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Verra' broadcastata in chiaro la tua posizione e il nickname a tutti i nodi mesh raggiungibili (max 7 hop).")
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showingFingerprintFor != nil && !showSidebar && viewModel.selectedPrivateChatPeer == nil },
            set: { _ in viewModel.showingFingerprintFor = nil }
        )) {
            if let peerID = viewModel.showingFingerprintFor {
                FingerprintView(viewModel: viewModel, peerID: peerID)
                    .environmentObject(viewModel)
            }
        }
#if os(iOS)
        // Only present image picker from main view when NOT in a sheet
        .fullScreenCover(isPresented: Binding(
            get: { showImagePicker && !showSidebar && viewModel.selectedPrivateChatPeer == nil },
            set: { newValue in
                if !newValue {
                    showImagePicker = false
                }
            }
        )) {
            ImagePickerView(sourceType: imagePickerSourceType) { image in
                showImagePicker = false
                viewModel.processThenSendImage(image)
            }
            .environmentObject(viewModel)
            .ignoresSafeArea()
        }
#endif
#if os(macOS)
        // Only present Mac image picker from main view when NOT in a sheet
        .sheet(isPresented: Binding(
            get: { showMacImagePicker && !showSidebar && viewModel.selectedPrivateChatPeer == nil },
            set: { newValue in
                if !newValue {
                    showMacImagePicker = false
                }
            }
        )) {
            MacImagePickerView { url in
                showMacImagePicker = false
                viewModel.processThenSendImage(from: url)
            }
            .environmentObject(viewModel)
        }
#endif
        .sheet(isPresented: Binding(
            get: { imagePreviewURL != nil },
            set: { presenting in if !presenting { imagePreviewURL = nil } }
        )) {
            if let url = imagePreviewURL {
                ImagePreviewView(url: url)
                    .environmentObject(viewModel)
            }
        }
        .alert("Recording Error", isPresented: $voiceRecordingVM.showAlert, actions: {
            Button("common.ok", role: .cancel) {}
            if voiceRecordingVM.state == .permissionDenied {
                Button("location_channels.action.open_settings") {
                    SystemSettings.microphone.open()
                }
            }
        }, message: {
            Text(voiceRecordingVM.state.alertMessage)
        })
        .alert("content.alert.bluetooth_required.title", isPresented: $viewModel.showBluetoothAlert) {
            Button("content.alert.bluetooth_required.settings") {
                SystemSettings.bluetooth.open()
            }
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(viewModel.bluetoothAlertMessage)
        }
        .sheet(isPresented: $showLocationChannelsSheet) {
            LocationChannelsSheet(isPresented: $showLocationChannelsSheet)
                .environmentObject(viewModel)
                .onAppear { viewModel.isLocationChannelsSheetPresented = true }
                .onDisappear { viewModel.isLocationChannelsSheetPresented = false }
        }
        .alert("content.alert.screenshot.title", isPresented: $viewModel.showScreenshotPrivacyWarning) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("content.alert.screenshot.message")
        }
        .onAppear {
            if case .mesh = locationManager.selectedChannel,
               locationManager.permissionState == .authorized,
               LocationChannelManager.shared.availableChannels.isEmpty {
                LocationChannelManager.shared.refreshChannels()
            }
        }
        .onChange(of: locationManager.selectedChannel) { _ in
            if case .mesh = locationManager.selectedChannel,
               locationManager.permissionState == .authorized,
               LocationChannelManager.shared.availableChannels.isEmpty {
                LocationChannelManager.shared.refreshChannels()
            }
        }
        .onChange(of: locationManager.permissionState) { _ in
            if case .mesh = locationManager.selectedChannel,
               locationManager.permissionState == .authorized,
               LocationChannelManager.shared.availableChannels.isEmpty {
                LocationChannelManager.shared.refreshChannels()
            }
        }
        .onDisappear {
            autocompleteDebounceTimer?.invalidate()
        }
    }
    
    // MARK: - Input View

    @ViewBuilder
    private var inputView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // @mentions autocomplete
            if viewModel.showAutocomplete && !viewModel.autocompleteSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.autocompleteSuggestions.prefix(4)), id: \.self) { suggestion in
                        Button(action: {
                            _ = viewModel.completeNickname(suggestion, in: &messageText)
                        }) {
                            HStack {
                                Text(suggestion)
                                    .font(.bitchatSystem(size: 11, design: .monospaced))
                                    .foregroundColor(textColor)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .background(Color.gray.opacity(0.1))
                    }
                }
                .background(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(secondaryTextColor.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 12)
            }

            CommandSuggestionsView(
                messageText: $messageText,
                textColor: textColor,
                backgroundColor: backgroundColor,
                secondaryTextColor: secondaryTextColor
            )

            if voiceRecordingVM.state.isActive {
                recordingIndicator
            }

            if showComposerActions {
                composerActionDrawer
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .center, spacing: 8) {
                composerPlusButton
                composerTextFieldPill
                composerSendOrMicButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(backgroundColor.opacity(0.95))
    }

    // MARK: - Side drawer & channel more (DESIGN.md §5, §9)

    @ViewBuilder
    private var channelMoreSheet: some View {
        ChannelMoreSheet(
            topic: selectedTopic,
            muted: $channelMuted,
            memberCount: viewModel.allPeers.count,
            onChannelInfo: handleChannelInfo,
            onMembers: handleChannelMembers,
            onSearch: handleChannelSearch,
            onLeave: handleChannelLeave
        )
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var sideDrawerOverlay: some View {
        if showSideDrawer {
            SideDrawerView(
                isOpen: $showSideDrawer,
                selectedTopic: $selectedTopic,
                channels: $managedChannels,
                nickname: viewModel.nickname,
                nodeShortID: String(viewModel.meshService.myPeerID.id.prefix(4)),
                nodesActive: viewModel.allPeers.filter { $0.isConnected || $0.isReachable }.count,
                onOpenSettings: handleDrawerOpenSettings
            )
            .transition(.move(edge: .leading))
            .zIndex(100)
        }
    }

    @ViewBuilder
    private var sideDrawerScrim: some View {
        if showSideDrawer {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        showSideDrawer = false
                    }
                }
                .transition(.opacity)
                .zIndex(99)
        }
    }

    private var themeColorScheme: ColorScheme? {
        switch themePreference {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    private func handleChannelInfo() {
        showChannelMore = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { showAppInfo = true }
    }
    private func handleChannelMembers() {
        showChannelMore = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { showSidebar = true }
    }
    private func handleChannelSearch() {
        showChannelMore = false
    }
    private func handleChannelLeave() {
        showChannelMore = false
        selectedTopic = "mesh"
    }
    private func handleDrawerOpenSettings() {
        showSideDrawer = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { showSettings = true }
    }

    // MARK: - Managed channels persistence

    private func loadManagedChannels() {
        guard managedChannels == ManagedChannel.defaults else { return }
        guard !managedChannelsBlob.isEmpty,
              let data = managedChannelsBlob.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([ManagedChannel].self, from: data),
              !decoded.isEmpty
        else { return }
        managedChannels = decoded
    }

    private func persistManagedChannels() {
        guard let data = try? JSONEncoder().encode(managedChannels),
              let s = String(data: data, encoding: .utf8)
        else { return }
        managedChannelsBlob = s
    }

    // MARK: - Composer subviews (DESIGN.md §5, §13)

    private var meshSurface2: Color {
        colorScheme == .dark
            ? Color(red: 0.110, green: 0.110, blue: 0.122) // #1C1C1F
            : Color(red: 0.949, green: 0.945, blue: 0.925) // #F2F1EC
    }

    private static let meshAccent = Color(red: 0.851, green: 0.467, blue: 0.341) // #D97757

    private var composerPlusButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showComposerActions.toggle()
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(textColor)
                    .rotationEffect(.degrees(showComposerActions ? 45 : 0))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(meshSurface2))

                if hasUnreadIncomingSOS && !showComposerActions {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(backgroundColor, lineWidth: 1.5))
                        .offset(x: 2, y: -2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show actions")
    }

    /// Most recent received SOS pin (from someone else) that the user has
    /// not yet acknowledged by opening the SOS map.
    private var hasUnreadIncomingSOS: Bool {
        guard let lastIncoming = viewModel.sosPins.last(where: { !$0.isOwn }) else {
            return false
        }
        return lastIncoming.id != lastSeenSOSID
    }

    private func markIncomingSOSAsSeen() {
        if let lastIncoming = viewModel.sosPins.last(where: { !$0.isOwn }) {
            lastSeenSOSID = lastIncoming.id
        }
    }

    private var composerTextFieldPill: some View {
        HStack(spacing: 0) {
            TextField(
                "",
                text: $messageText,
                prompt: Text(
                    String(localized: "content.input.message_placeholder", comment: "Placeholder shown in the chat composer")
                )
                .foregroundColor(secondaryTextColor.opacity(0.55))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundColor(textColor)
            .focused($isTextFieldFocused)
            .autocorrectionDisabled(true)
#if os(iOS)
            .textInputAutocapitalization(.sentences)
#endif
            .submitLabel(.send)
            .onSubmit { sendMessage() }
            .modifier(FocusEffectDisabledModifier())
            .onChange(of: messageText) { newValue in
                autocompleteDebounceTimer?.invalidate()
                autocompleteDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak viewModel] _ in
                    let cursorPosition = newValue.count
                    Task { @MainActor in
                        viewModel?.updateAutocomplete(for: newValue, cursorPosition: cursorPosition)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(Capsule(style: .continuous).fill(meshSurface2))
    }

    @ViewBuilder
    private var composerSendOrMicButton: some View {
        let hasText = !messageText.trimmed.isEmpty
        if shouldShowVoiceControl && !hasText {
            micButtonView
                .frame(width: 38, height: 38)
                .background(Circle().fill(meshSurface2))
        } else {
            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(hasText ? .white : textColor.opacity(0.4))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(hasText ? Self.meshAccent : meshSurface2))
            }
            .buttonStyle(.plain)
            .disabled(!hasText)
            .accessibilityLabel(
                String(localized: "content.accessibility.send_message", comment: "Accessibility label for the send message button")
            )
        }
    }

    private var composerActionDrawer: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ComposerActionTile(
                    icon: "exclamationmark.octagon",
                    label: "sos",
                    danger: true
                ) {
                    closeActionsAnd { showSOSConfirm = true }
                }
                ComposerActionTile(
                    icon: "map",
                    label: "mappa",
                    showBadge: hasUnreadIncomingSOS
                ) {
                    closeActionsAnd { showSOSMapSheet = true }
                }
                ComposerActionTile(icon: "dot.radiowaves.left.and.right", label: "radar") {
                    closeActionsAnd { showRadarSheet = true }
                }
#if os(iOS)
                ComposerActionTile(icon: "camera", label: "foto") {
                    closeActionsAnd {
                        imagePickerSourceType = .photoLibrary
                        showImagePicker = true
                    }
                }
#endif
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 78)
    }

    private func closeActionsAnd(_ then: @escaping () -> Void) {
        withAnimation(.easeInOut(duration: 0.18)) { showComposerActions = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: then)
    }

    // MARK: - Actions
    
    private func sendMessage() {
        guard let trimmed = messageText.trimmedOrNilIfEmpty else { return }

        // Clear input immediately for instant feedback
        messageText = ""

        // Defer actual send to next runloop to avoid blocking
        DispatchQueue.main.async {
            self.viewModel.sendMessage(trimmed)
        }
    }
    
    // MARK: - Sheet Content
    
    private var peopleSheetView: some View {
        NavigationStack {
            Group {
                if viewModel.selectedPrivateChatPeer != nil {
                    privateChatSheetView
                } else {
                    peopleListSheetView
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { viewModel.showingFingerprintFor != nil && (showSidebar || viewModel.selectedPrivateChatPeer != nil) },
                set: { isPresented in
                    if !isPresented {
                        viewModel.showingFingerprintFor = nil
                    }
                }
            )) {
                if let peerID = viewModel.showingFingerprintFor {
                    FingerprintView(viewModel: viewModel, peerID: peerID)
                        .environmentObject(viewModel)
                }
            }
        }
        .background(backgroundColor)
        .foregroundColor(textColor)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
        // Present image picker from sheet context when IN a sheet (parent-child pattern)
        #if os(iOS)
        .fullScreenCover(isPresented: Binding(
            get: { showImagePicker && (showSidebar || viewModel.selectedPrivateChatPeer != nil) },
            set: { newValue in
                if !newValue {
                    showImagePicker = false
                }
            }
        )) {
            ImagePickerView(sourceType: imagePickerSourceType) { image in
                showImagePicker = false
                viewModel.processThenSendImage(image)
            }
            .environmentObject(viewModel)
            .ignoresSafeArea()
        }
        #endif
        #if os(macOS)
        .sheet(isPresented: $showMacImagePicker) {
            MacImagePickerView { url in
                showMacImagePicker = false
                viewModel.processThenSendImage(from: url)
            }
            .environmentObject(viewModel)
        }
        #endif
    }
    
    // MARK: - People Sheet Views
    
    private var peopleListSheetView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(peopleSheetTitle)
                        .font(.bitchatSystem(size: 18, design: .monospaced))
                        .foregroundColor(textColor)
                    Spacer()
                    if case .mesh = locationManager.selectedChannel {
                        Button(action: { showVerifySheet = true }) {
                            Image(systemName: "qrcode")
                                .font(.bitchatSystem(size: 14))
                        }
                        .buttonStyle(.plain)
                        .help(
                            String(localized: "content.help.verification", comment: "Help text for verification button")
                        )
                    }
                    Button(action: {
                        withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                            dismiss()
                            showSidebar = false
                            showVerifySheet = false
                            viewModel.endPrivateChat()
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.bitchatSystem(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                let activeText = String.localizedStringWithFormat(
                    String(localized: "%@ active", comment: "Count of active users in the people sheet"),
                    "\(peopleSheetActiveCount)"
                )

                if let subtitle = peopleSheetSubtitle {
                    let subtitleColor: Color = {
                        switch locationManager.selectedChannel {
                        case .mesh:
                            return Color.blue
                        case .location:
                            return Color(red: 0.851, green: 0.467, blue: 0.341)
                        }
                    }()
                    HStack(spacing: 6) {
                        Text(subtitle)
                            .foregroundColor(subtitleColor)
                        Text(activeText)
                            .foregroundColor(.secondary)
                    }
                    .font(.bitchatSystem(size: 12, design: .monospaced))
                } else {
                    Text(activeText)
                        .font(.bitchatSystem(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(backgroundColor)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if case .location = locationManager.selectedChannel {
                        GeohashPeopleList(
                            viewModel: viewModel,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            onTapPerson: {
                                showSidebar = true
                            }
                        )
                    } else {
                        MeshPeerList(
                            viewModel: viewModel,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            onTapPeer: { peerID in
                                viewModel.startPrivateChat(with: peerID)
                                showSidebar = true
                            },
                            onToggleFavorite: { peerID in
                                viewModel.toggleFavorite(peerID: peerID)
                            },
                            onShowFingerprint: { peerID in
                                viewModel.showFingerprint(for: peerID)
                            }
                        )
                    }
                }
                .padding(.top, 4)
                .id(viewModel.allPeers.map { "\($0.peerID)-\($0.isConnected)" }.joined())
            }
        }
    }
    
    // MARK: - View Components

    private var privateChatSheetView: some View {
        VStack(spacing: 0) {
            if let privatePeerID = viewModel.selectedPrivateChatPeer {
                let headerContext = makePrivateHeaderContext(for: privatePeerID)

                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                            viewModel.endPrivateChat()
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.bitchatSystem(size: 12))
                            .foregroundColor(textColor)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String(localized: "content.accessibility.back_to_main_chat", comment: "Accessibility label for returning to main chat")
                    )

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        privateHeaderInfo(context: headerContext, privatePeerID: privatePeerID)
                        let isFavorite = viewModel.isFavorite(peerID: headerContext.headerPeerID)

                        if !privatePeerID.isGeoDM {
                            Button(action: {
                                viewModel.toggleFavorite(peerID: headerContext.headerPeerID)
                            }) {
                                Image(systemName: isFavorite ? "star.fill" : "star")
                                    .font(.bitchatSystem(size: 14))
                                    .foregroundColor(isFavorite ? Color.yellow : textColor)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                isFavorite
                                ? String(localized: "content.accessibility.remove_favorite", comment: "Accessibility label to remove a favorite")
                                : String(localized: "content.accessibility.add_favorite", comment: "Accessibility label to add a favorite")
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 0)

                    Button(action: {
                        withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                            viewModel.endPrivateChat()
                            showSidebar = true
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.bitchatSystem(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 32, height: 32)
                    }
                
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .frame(height: headerHeight)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(backgroundColor)
            }

            MessageListView(
                privatePeer: viewModel.selectedPrivateChatPeer,
                isAtBottom: $isAtBottomPrivate,
                messageText: $messageText,
                selectedMessageSender: $selectedMessageSender,
                selectedMessageSenderID: $selectedMessageSenderID,
                imagePreviewURL: $imagePreviewURL,
                windowCountPublic: $windowCountPublic,
                windowCountPrivate: $windowCountPrivate,
                showSidebar: $showSidebar,
                isTextFieldFocused: $isTextFieldFocused,
            )
            .background(backgroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            inputView
        }
        .background(backgroundColor)
        .foregroundColor(textColor)
        .highPriorityGesture(
            DragGesture(minimumDistance: 25, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = abs(value.translation.height)
                    guard horizontal > 80, vertical < 60 else { return }
                    withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                        showSidebar = true
                        viewModel.endPrivateChat()
                    }
                }
        )
    }

    private func privateHeaderInfo(context: PrivateHeaderContext, privatePeerID: PeerID) -> some View {
        Button(action: {
            viewModel.showFingerprint(for: context.headerPeerID)
        }) {
            HStack(spacing: 6) {
                if let connectionState = context.peer?.connectionState {
                    switch connectionState {
                    case .bluetoothConnected:
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.bitchatSystem(size: 14))
                            .foregroundColor(textColor)
                            .accessibilityLabel(String(localized: "content.accessibility.connected_mesh", comment: "Accessibility label for mesh-connected peer indicator"))
                    case .meshReachable:
                        Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                            .font(.bitchatSystem(size: 14))
                            .foregroundColor(textColor)
                            .accessibilityLabel(String(localized: "content.accessibility.reachable_mesh", comment: "Accessibility label for mesh-reachable peer indicator"))
                    case .nostrAvailable:
                        Image(systemName: "globe")
                            .font(.bitchatSystem(size: 14))
                            .foregroundColor(.purple)
                            .accessibilityLabel(String(localized: "content.accessibility.available_nostr", comment: "Accessibility label for Nostr-available peer indicator"))
                    case .offline:
                        EmptyView()
                    }
                } else if viewModel.meshService.isPeerReachable(context.headerPeerID) {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.bitchatSystem(size: 14))
                        .foregroundColor(textColor)
                        .accessibilityLabel(String(localized: "content.accessibility.reachable_mesh", comment: "Accessibility label for mesh-reachable peer indicator"))
                } else if context.isNostrAvailable {
                    Image(systemName: "globe")
                        .font(.bitchatSystem(size: 14))
                        .foregroundColor(.purple)
                        .accessibilityLabel(String(localized: "content.accessibility.available_nostr", comment: "Accessibility label for Nostr-available peer indicator"))
                } else if viewModel.meshService.isPeerConnected(context.headerPeerID) || viewModel.connectedPeers.contains(context.headerPeerID) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.bitchatSystem(size: 14))
                        .foregroundColor(textColor)
                        .accessibilityLabel(String(localized: "content.accessibility.connected_mesh", comment: "Accessibility label for mesh-connected peer indicator"))
                }

                Text(context.displayName)
                    .font(.bitchatSystem(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(textColor)

                if !privatePeerID.isGeoDM {
                    let statusPeerID = viewModel.getShortIDForNoiseKey(privatePeerID)
                    let encryptionStatus = viewModel.getEncryptionStatus(for: statusPeerID)
                    if let icon = encryptionStatus.icon {
                        Image(systemName: icon)
                            .font(.bitchatSystem(size: 14))
                            .foregroundColor(encryptionStatus == .noiseVerified ? textColor :
                                             encryptionStatus == .noiseSecured ? textColor :
                                             Color.red)
                            .accessibilityLabel(
                                String(
                                    format: String(localized: "content.accessibility.encryption_status", comment: "Accessibility label announcing encryption status"),
                                    locale: .current,
                                    encryptionStatus.accessibilityDescription
                                )
                            )
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(
                format: String(localized: "content.accessibility.private_chat_header", comment: "Accessibility label describing the private chat header"),
                locale: .current,
                context.displayName
            )
        )
        .accessibilityHint(
            String(localized: "content.accessibility.view_fingerprint_hint", comment: "Accessibility hint for viewing encryption fingerprint")
        )
        .frame(height: headerHeight)
    }

    private func makePrivateHeaderContext(for privatePeerID: PeerID) -> PrivateHeaderContext {
        let headerPeerID = viewModel.getShortIDForNoiseKey(privatePeerID)
        let peer = viewModel.getPeer(byID: headerPeerID)

        let displayName: String = {
            if privatePeerID.isGeoDM, case .location(let ch) = locationManager.selectedChannel {
                let disp = viewModel.geohashDisplayName(for: privatePeerID)
                return "#\(ch.geohash)/@\(disp)"
            }
            if let name = peer?.displayName { return name }
            if let name = viewModel.meshService.peerNickname(peerID: headerPeerID) { return name }
            if let fav = FavoritesPersistenceService.shared.getFavoriteStatus(for: Data(hexString: headerPeerID.id) ?? Data()),
               !fav.peerNickname.isEmpty { return fav.peerNickname }
            if headerPeerID.id.count == 16 {
                let candidates = viewModel.identityManager.getCryptoIdentitiesByPeerIDPrefix(headerPeerID)
                if let id = candidates.first,
                   let social = viewModel.identityManager.getSocialIdentity(for: id.fingerprint) {
                    if let pet = social.localPetname, !pet.isEmpty { return pet }
                    if !social.claimedNickname.isEmpty { return social.claimedNickname }
                }
            } else if let keyData = headerPeerID.noiseKey {
                let fp = keyData.sha256Fingerprint()
                if let social = viewModel.identityManager.getSocialIdentity(for: fp) {
                    if let pet = social.localPetname, !pet.isEmpty { return pet }
                    if !social.claimedNickname.isEmpty { return social.claimedNickname }
                }
            }
            return String(localized: "common.unknown", comment: "Fallback label for unknown peer")
        }()

        let isNostrAvailable: Bool = {
            guard let connectionState = peer?.connectionState else {
                if let noiseKey = Data(hexString: headerPeerID.id),
                   let favoriteStatus = FavoritesPersistenceService.shared.getFavoriteStatus(for: noiseKey),
                   favoriteStatus.isMutual {
                    return true
                }
                return false
            }
            return connectionState == .nostrAvailable
        }()

        return PrivateHeaderContext(
            headerPeerID: headerPeerID,
            peer: peer,
            displayName: displayName,
            isNostrAvailable: isNostrAvailable
        )
    }

    // Compute channel-aware people count and color for toolbar (cross-platform)
    private func channelPeopleCountAndColor() -> (Int, Color) {
        switch locationManager.selectedChannel {
        case .location:
            let n = viewModel.geohashPeople.count
            let standardGreen = (colorScheme == .dark) ? Color(red: 0.851, green: 0.467, blue: 0.341) : Color(red: 0.722, green: 0.351, blue: 0.231)
            return (n, n > 0 ? standardGreen : Color.secondary)
        case .mesh:
            let counts = viewModel.allPeers.reduce(into: (others: 0, mesh: 0)) { counts, peer in
                guard peer.peerID != viewModel.meshService.myPeerID else { return }
                if peer.isConnected { counts.mesh += 1; counts.others += 1 }
                else if peer.isReachable { counts.others += 1 }
            }
            let meshBlue = Color(hue: 0.60, saturation: 0.85, brightness: 0.82)
            let color: Color = counts.mesh > 0 ? meshBlue : Color.secondary
            return (counts.others, color)
        }
    }

    
    private var mainHeaderView: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    showSideDrawer = true
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(textColor)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Side menu")

            channelTitleView
                .onTapGesture { showChannelManager = true }
                .onLongPressGesture(minimumDuration: 0.8) {
                    viewModel.panicClearAllData()
                }

            Spacer()
            
            headerTrailingActions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var channelTitleView: some View {
        HStack(spacing: 0) {
            Text("#")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Self.meshAccent)
            Text(selectedTopic)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)
                .foregroundColor(textColor)
        }
    }

    @ViewBuilder
    private var headerTrailingActions: some View {
        HStack(spacing: 4) {
            if viewModel.hasAnyUnreadMessages {
                Button(action: { viewModel.openMostRelevantPrivateChat() }) {
                    Image(systemName: "envelope")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(Self.meshAccent)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    String(localized: "content.accessibility.open_unread_private_chat", comment: "Accessibility label for the unread private chat button")
                )
            }
            Button(action: { showChannelMore = true }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(textColor)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Channel actions")
        }
    }

    var statusStripView: some View {
        let reachable = viewModel.allPeers.filter { $0.isReachable || $0.isConnected }.count
        return HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.122, green: 0.541, blue: 0.357).opacity(0.18))
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(Color(red: 0.122, green: 0.541, blue: 0.357))
                    .frame(width: 6, height: 6)
            }
            Text("mesh attiva")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(textColor)
            Text("·")
                .font(.system(size: 12))
                .foregroundColor(secondaryTextColor.opacity(0.5))
            Text("\(reachable) \(reachable == 1 ? "nodo" : "nodi")")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundColor(secondaryTextColor)
            Spacer()
            Image(systemName: "battery.75")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(secondaryTextColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(meshSurface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

}

// MARK: - Helper Views

private extension ContentView {
    var recordingIndicator: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .foregroundColor(.red)
                .font(.bitchatSystem(size: 20))
            TimelineView(.periodic(from: .now, by: 0.05)) { context in
                Text(
                    "recording \(voiceRecordingVM.formattedDuration(for: context.date))",
                    comment: "Voice note recording duration indicator"
                )
                .font(.bitchatSystem(size: 13, design: .monospaced))
                .foregroundColor(.red)
            }
            Spacer()
            Button(action: voiceRecordingVM.cancel) {
                Label("Cancel", systemImage: "xmark.circle")
                    .labelStyle(.iconOnly)
                    .font(.bitchatSystem(size: 18))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.15))
        )
    }

    private var shouldShowMediaControls: Bool {
        if let peer = viewModel.selectedPrivateChatPeer, !(peer.isGeoDM || peer.isGeoChat) {
            return true
        }
        switch locationManager.selectedChannel {
        case .mesh:
            return true
        case .location:
            return false
        }
    }

    private var shouldShowVoiceControl: Bool {
        if let peer = viewModel.selectedPrivateChatPeer, !(peer.isGeoDM || peer.isGeoChat) {
            return true
        }
        switch locationManager.selectedChannel {
        case .mesh:
            return true
        case .location:
            return false
        }
    }

    private var composerAccentColor: Color {
        viewModel.selectedPrivateChatPeer != nil ? Color.orange : textColor
    }

    var attachmentButton: some View {
        #if os(iOS)
        Image(systemName: "camera")
            .font(.system(size: 24, weight: .regular))
            .foregroundColor(Color.secondary)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .onTapGesture {
                // Tap = Photo Library
                imagePickerSourceType = .photoLibrary
                showImagePicker = true
            }
            .onLongPressGesture(minimumDuration: 0.3) {
                // Long press = Camera
                imagePickerSourceType = .camera
                showImagePicker = true
            }
            .accessibilityLabel("Tap for library, long press for camera")
        #else
        Button(action: { showMacImagePicker = true }) {
            Image(systemName: "photo")
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(Color.secondary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose photo")
        #endif
    }

    @ViewBuilder
    var sendOrMicButton: some View {
        let hasText = !messageText.trimmed.isEmpty
        if shouldShowVoiceControl {
            ZStack {
                micButtonView
                    .opacity(hasText ? 0 : 1)
                    .allowsHitTesting(!hasText)
                sendButtonView(enabled: hasText)
                    .opacity(hasText ? 1 : 0)
                    .allowsHitTesting(hasText)
            }
            .frame(width: 30, height: 30)
        } else {
            sendButtonView(enabled: hasText)
                .frame(width: 30, height: 30)
        }
    }

    private var micButtonView: some View {
        Image(systemName: "mic")
            .font(.system(size: 24, weight: .regular))
            .foregroundColor(voiceRecordingVM.state.isActive ? Color.red : Color.secondary)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .overlay(
                Color.clear
                    .contentShape(Circle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in voiceRecordingVM.start(shouldShow: shouldShowVoiceControl) }
                            .onEnded { _ in voiceRecordingVM.finish(completion: viewModel.sendVoiceNote) }
                    )
            )
            .accessibilityLabel("Hold to record a voice note")
    }

    private func sendButtonView(enabled: Bool) -> some View {
        let activeColor = Color(red: 0.851, green: 0.467, blue: 0.341)
        return Button(action: sendMessage) {
            Image(systemName: "paperplane")
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(enabled ? activeColor : Color.secondary.opacity(0.5))
                .frame(width: 30, height: 30)
                .rotationEffect(.degrees(45))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(
            String(localized: "content.accessibility.send_message", comment: "Accessibility label for the send message button")
        )
        .accessibilityHint(
            enabled
            ? String(localized: "content.accessibility.send_hint_ready", comment: "Hint prompting the user to send the message")
            : String(localized: "content.accessibility.send_hint_empty", comment: "Hint prompting the user to enter a message")
        )
    }
}

// MARK: - SOS Broadcast (meshcomm)

/// Big red panic button. Confirms via dialog, fetches a one-shot CoreLocation
/// fix (with a 5s safety timeout), and emits a `[SOS]` broadcast over the
/// active BLE mesh transport regardless of the active channel.
struct SOSButton: View {
    let viewModel: ChatViewModel
    @StateObject private var locator = SOSLocationFetcher()
    @State private var showConfirmation = false
    @State private var sending = false

    var body: some View {
        Button {
            showConfirmation = true
        } label: {
            Image(systemName: "exclamationmark.octagon")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Color.red)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sending)
        .accessibilityLabel("SOS broadcast")
        .confirmationDialog(
            "Inviare SOS broadcast?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Invia SOS", role: .destructive) {
                sending = true
                Task { @MainActor in
                    let coord = await locator.fetchOnce()
                    viewModel.sendSOSMessage(
                        latitude: coord?.latitude,
                        longitude: coord?.longitude
                    )
                    sending = false
                }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Verra' broadcastata in chiaro la tua posizione e il nickname a tutti i nodi mesh raggiungibili (max 7 hop).")
        }
    }
}

@MainActor
final class SOSLocationFetcher: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var awaitingAuth = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func fetchOnce() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.startFlow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.finish(nil)
            }
        }
    }

    private func startFlow() {
        switch manager.authorizationStatus {
        case .notDetermined:
            awaitingAuth = true
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(nil)
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        @unknown default:
            finish(nil)
        }
    }

    private func finish(_ coord: CLLocationCoordinate2D?) {
        guard let cont = self.continuation else { return }
        self.continuation = nil
        cont.resume(returning: coord)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.awaitingAuth else { return }
            self.awaitingAuth = false
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                self.finish(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coord = locations.last?.coordinate
        Task { @MainActor in
            self.finish(coord)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.finish(nil)
        }
    }
}

// MARK: - SOS Map (meshcomm)

/// Toolbar button that surfaces the SOS map as a sheet. The icon turns
/// orange when there is at least one SOS pin to view, otherwise it dims.
struct SOSMapButton: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showingSheet = false

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            Image(systemName: "map")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(
                    viewModel.sosPins.isEmpty
                    ? Color.secondary
                    : Color(red: 0.851, green: 0.467, blue: 0.341)
                )
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open SOS map")
        .sheet(isPresented: $showingSheet) {
            SOSMapView(pins: viewModel.sosPins)
        }
    }
}

struct SOSMapView: View {
    let pins: [SOSPin]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MeshMapRepresentable(pins: pins)
                    .ignoresSafeArea(edges: .bottom)

                if pins.isEmpty {
                    emptyState
                } else {
                    pinsLegend
                }
            }
            .navigationTitle("SOS map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("nessun SOS sulla mappa")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("// pin appariranno qui quando ricevi un broadcast [SOS] con coordinate")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }

    private var pinsLegend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(pins.suffix(4)) { pin in
                HStack(spacing: 6) {
                    Circle()
                        .fill(pin.isOwn ? Color.blue : Color.red)
                        .frame(width: 8, height: 8)
                    Text("\(pin.nickname)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text(String(format: "@%.4f,%.4f", pin.latitude, pin.longitude))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

/// `MKMapView` wrapper rendering SOS pins on Apple Maps. We previously tried
/// to use OpenStreetMap tiles for offline caching, but their public tile
/// server returns HTTP 403 to third-party apps (per their tile usage
/// policy), which corrupts the cache with "Access blocked" tiles. We now
/// rely on Apple Maps and clean up any leftover OSM cache at first load.
struct MeshMapRepresentable: UIViewRepresentable {
    let pins: [SOSPin]

    func makeUIView(context: Context) -> MKMapView {
        // Purge any stale OSM tile cache so previously poisoned tiles don't
        // overlay Apple Maps. Idempotent: removes the directory if present.
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let stale = docs.appendingPathComponent("meshcomm-tiles", isDirectory: true)
            try? FileManager.default.removeItem(at: stale)
        }
        let map = MKMapView()
        map.showsUserLocation = true
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let existing = map.annotations.compactMap { $0 as? MKPointAnnotation }
        map.removeAnnotations(existing)
        for pin in pins {
            let ann = MKPointAnnotation()
            ann.coordinate = pin.coordinate
            ann.title = pin.nickname
            ann.subtitle = pin.isOwn ? "SOS (you)" : "SOS"
            map.addAnnotation(ann)
        }
        if let last = pins.last {
            let region = MKCoordinateRegion(
                center: last.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            map.setRegion(region, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// Note: a previous build shipped a `MeshOfflineTileOverlay` and a
// `MeshTilePrefetcher` that pulled tiles from `tile.openstreetmap.org`.
// OSM's volunteer-run tile server returns HTTP 403 to third-party apps
// (see osm.wiki/Blocked) so those tiles ended up rendering as "Access
// blocked" warnings. We removed the prefetch path entirely and rely on
// Apple Maps inside MKMapView. To bring real offline tiles back we need
// either a paid provider (Mapbox/MapTiler/Stadia) or our own tile server.

// MARK: - Proximity Radar (meshcomm)

/// Toolbar button that surfaces the proximity radar sheet. Trend arrows are
/// computed from BLE RSSI history collected by `ProximityTracker`.
struct RadarButton: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showingSheet = false

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Color.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open proximity radar")
        .sheet(isPresented: $showingSheet) {
            RadarSheetView(viewModel: viewModel)
        }
    }
}

struct RadarSheetView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    @State private var rows: [RadarRowData] = []
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty {
                    emptyState
                } else {
                    List(rows) { row in
                        RadarRow(row: row)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("proximity radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                    .accessibilityLabel("Close")
                }
            }
            .onAppear {
                refresh()
                refreshTask = Task { @MainActor in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        if Task.isCancelled { break }
                        refresh()
                    }
                }
            }
            .onDisappear { refreshTask?.cancel() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("nessun peer in raggio BLE")
                .font(.system(size: 14, design: .monospaced))
            Text("// avvicinati a un altro device meshcomm e attendi qualche secondo")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func refresh() {
        let all = ProximityTracker.shared.allReadings()
        var built: [RadarRowData] = []
        for peer in viewModel.allPeers {
            guard let reading = all[peer.peerID] else { continue }
            built.append(RadarRowData(
                id: peer.peerID,
                nickname: peer.nickname,
                shortID: String(peer.peerID.id.prefix(6)),
                reading: reading
            ))
        }
        built.sort { $0.reading.rssiSmoothed > $1.reading.rssiSmoothed }
        rows = built
    }
}

struct RadarRowData: Identifiable {
    let id: PeerID
    let nickname: String
    let shortID: String
    let reading: ProximityTracker.Reading
}

struct RadarRow: View {
    let row: RadarRowData

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: trendIcon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(trendColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.nickname)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                    Text(row.shortID)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(trendLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedDistance)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Text("\(row.reading.rssiSmoothed) dBm")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var trendIcon: String {
        switch row.reading.trend {
        case .approaching: return "arrow.up.right.circle.fill"
        case .receding: return "arrow.down.right.circle.fill"
        case .stable: return "circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var trendColor: Color {
        switch row.reading.trend {
        case .approaching: return Color(red: 0.529, green: 0.682, blue: 0.420)
        case .receding: return Color(red: 0.760, green: 0.330, blue: 0.314)
        case .stable: return Color(red: 0.851, green: 0.467, blue: 0.341)
        case .unknown: return .secondary
        }
    }

    private var trendLabel: String {
        switch row.reading.trend {
        case .approaching: return "in avvicinamento"
        case .receding: return "in allontanamento"
        case .stable: return "distanza stabile"
        case .unknown: return "calibrazione..."
        }
    }

    private var formattedDistance: String {
        let m = row.reading.approxMeters
        if m < 10 { return String(format: "≈%.1f m", m) }
        return String(format: "≈%.0f m", m)
    }
}

// MARK: - Settings Sheet (meshcomm)

/// Drawer-style settings sheet opened from the hamburger button at the top
/// of the chat header. Lets the user rename their callsign, browse SOS map
/// and radar shortcuts, and trigger an emergency wipe.
struct SettingsSheet: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    @State private var draftNickname: String = ""
    @State private var savedToast: Bool = false
    @AppStorage("meshcomm.themePreference") private var themePreference: String = "system"

    private let accent = Color(red: 0.851, green: 0.467, blue: 0.341)

    var body: some View {
        NavigationStack {
            List {
                identitySection
                appearanceSection
                toolsSection
                aboutSection
                dangerSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
            }
            .onAppear { draftNickname = viewModel.nickname }
        }
        .preferredColorScheme(localColorScheme)
    }

    private var localColorScheme: ColorScheme? {
        switch themePreference {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    private var identitySection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(accent)
                TextField("callsign", text: $draftNickname)
                    .font(.system(size: 16))
                    .autocorrectionDisabled(true)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { saveNickname() }
                if canSave {
                    Button("salva", action: saveNickname)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            if savedToast {
                Label("nickname salvato", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.122, green: 0.541, blue: 0.357))
            }
        } header: {
            Text("identita'")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
        } footer: {
            Text("Callsign annunciato sui pacchetti HELLO. Visibile a tutti i peer.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker(selection: $themePreference) {
                Text("sistema").tag("system")
                Text("chiaro").tag("light")
                Text("scuro").tag("dark")
            } label: {
                Label {
                    Text("tema")
                        .font(.system(size: 15))
                } icon: {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(accent)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("aspetto")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
    }

    private var toolsSection: some View {
        Section {
            NavigationLink {
                SOSMapView(pins: viewModel.sosPins)
            } label: {
                Label {
                    HStack {
                        Text("mappa SOS").font(.system(size: 15))
                        Spacer()
                        Text("\(viewModel.sosPins.count)")
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "map").foregroundStyle(accent)
                }
            }
            NavigationLink {
                RadarSheetView(viewModel: viewModel)
            } label: {
                Label {
                    Text("radar di prossimita'").font(.system(size: 15))
                } icon: {
                    Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(accent)
                }
            }
        } header: {
            Text("strumenti")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Label {
                    Text("OpenChat").font(.system(size: 15))
                } icon: {
                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(accent)
                }
                Spacer()
                Text("v1.0").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack {
                Label {
                    Text("fork di bitchat").font(.system(size: 13)).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary)
                }
                Spacer()
                Text("Unlicense").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Link(destination: URL(string: "https://github.com/edoardomartinelli-parkpass/meshcomm")!) {
                Label {
                    Text("github / source").font(.system(size: 14))
                } icon: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(accent)
                }
            }
        } header: {
            Text("info")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                viewModel.panicClearAllData()
                dismiss()
            } label: {
                Label {
                    Text("emergency wipe").font(.system(size: 15, weight: .semibold))
                } icon: {
                    Image(systemName: "trash")
                }
            }
        } header: {
            Text("danger zone")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color(red: 0.753, green: 0.212, blue: 0.173))
        } footer: {
            Text("Cancella keypair, cronologia chat e pin SOS. Irreversibile.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var canSave: Bool {
        let trimmed = draftNickname.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != viewModel.nickname
    }

    private func saveNickname() {
        let trimmed = draftNickname.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != viewModel.nickname else { return }
        viewModel.nickname = trimmed
        viewModel.validateAndSaveNickname()
        savedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            savedToast = false
        }
    }
}

// MARK: - Side drawer & channel more sheet (DESIGN.md §9, §5)

/// Slide-from-left drawer matching the Claude design: profile card,
/// 3-stat row (active nodes, hop max, battery), channels list, footer
/// actions (map, settings). Tap a channel to set it as the active topic.
struct SideDrawerView: View {
    @Binding var isOpen: Bool
    @Binding var selectedTopic: String
    @Binding var channels: [ManagedChannel]
    let nickname: String
    let nodeShortID: String
    let nodesActive: Int
    let onOpenSettings: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var batteryLevel: Float = -1
    @State private var batteryTimer: Timer?

    private static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)
    private static let danger = Color(red: 0.753, green: 0.212, blue: 0.173)

    private var bg: Color {
        colorScheme == .dark
            ? Color(red: 0.043, green: 0.043, blue: 0.047)
            : Color(red: 0.980, green: 0.980, blue: 0.969)
    }
    private var surface2: Color {
        colorScheme == .dark
            ? Color(red: 0.110, green: 0.110, blue: 0.122)
            : Color(red: 0.949, green: 0.945, blue: 0.925)
    }
    private var muted: Color {
        colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.5)
    }
    private var faint: Color {
        colorScheme == .dark ? Color.white.opacity(0.32) : Color.black.opacity(0.32)
    }

    var body: some View {
        GeometryReader { geo in
            drawerContent
                .frame(width: min(geo.size.width * 0.82, 320))
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background(bg)
                .shadow(color: .black.opacity(0.18), radius: 30, x: 4, y: 0)
        }
        .ignoresSafeArea()
        .onAppear {
            #if os(iOS)
            UIDevice.current.isBatteryMonitoringEnabled = true
            batteryLevel = UIDevice.current.batteryLevel
            batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                batteryLevel = UIDevice.current.batteryLevel
            }
            #endif
        }
        .onDisappear {
            batteryTimer?.invalidate()
            batteryTimer = nil
        }
    }

    private var batteryDisplay: String {
        if batteryLevel < 0 { return "—" }
        return "\(Int((batteryLevel * 100).rounded()))%"
    }

    private var drawerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileCard
            statsRow
            channelsHeader
            channelsList
            Spacer(minLength: 0)
            footer
        }
        .padding(.top, 54)
    }

    private var profileCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Self.accent.opacity(0.18))
                Text(String(nickname.prefix(2)).lowercased())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Self.accent)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(nickname.isEmpty ? "edoardo" : nickname)")
                    .font(.system(size: 15, weight: .semibold))
                Text("node · \(nodeShortID.isEmpty ? "7f3a" : nodeShortID) · online")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(muted)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private var statsRow: some View {
        HStack(alignment: .center, spacing: 0) {
            statCell(value: "\(nodesActive)", label: "nodi attivi")
            Rectangle().fill(faint).frame(width: 0.5, height: 28)
            statCell(value: "3", label: "hop max")
            Rectangle().fill(faint).frame(width: 0.5, height: 28)
            statCell(value: batteryDisplay, label: "batteria")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(surface2, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(muted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private var channelsHeader: some View {
        Text("CANALI")
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(faint)
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 8)
    }

    private var channelsList: some View {
        VStack(spacing: 2) {
            ForEach(channels) { ch in
                Button {
                    selectedTopic = ch.name
                    close()
                } label: {
                    HStack(spacing: 12) {
                        Text("#")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ch.isDanger
                                ? Self.danger
                                : (ch.name == selectedTopic ? Self.accent : muted))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ch.name)
                                .font(.system(size: 14, weight: ch.name == selectedTopic ? .semibold : .medium))
                            Text(ch.hint)
                                .font(.system(size: 11))
                                .foregroundStyle(muted)
                                .lineLimit(1)
                        }
                        Spacer()
                        if ch.unread > 0 {
                            Text("\(ch.unread)")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Self.accent, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        ch.name == selectedTopic ? surface2 : .clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
    }

    private var footer: some View {
        VStack(spacing: 2) {
            Rectangle().fill(faint).frame(height: 0.5)
                .padding(.bottom, 4)
            footerItem(icon: "ellipsis", label: "impostazioni", action: onOpenSettings)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 22)
    }

    private func footerItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(muted)
                    .frame(width: 24)
                Text(label)
                    .font(.system(size: 14))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isOpen = false
        }
    }
}

/// Bottom-sheet matching the Claude design: title (CANALE + #topic),
/// then a vertical list of 6 actions (silenzia, info, membri, condividi
/// posizione live, cerca, esci). Routes back to existing flows via the
/// provided closures.
struct ChannelMoreSheet: View {
    let topic: String
    @Binding var muted: Bool
    let memberCount: Int
    let onChannelInfo: () -> Void
    let onMembers: () -> Void
    let onSearch: () -> Void
    let onLeave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)
    private static let danger = Color(red: 0.753, green: 0.212, blue: 0.173)

    var body: some View {
        VStack(spacing: 0) {
            header
            actions
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("#")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Self.accent)
            Text(topic)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private var actions: some View {
        VStack(spacing: 0) {
            row(icon: "antenna.radiowaves.left.and.right", label: muted ? "riattiva notifiche" : "silenzia canale") {
                muted.toggle()
                dismiss()
            }
            row(icon: "ellipsis", label: "info canale", action: onChannelInfo)
            row(icon: "line.3.horizontal", label: "membri (\(memberCount))", action: onMembers)
            row(icon: "map", label: "cerca nei messaggi", action: onSearch)
            row(icon: "exclamationmark.octagon", label: "esci dal canale", danger: true, action: onLeave)
        }
        .padding(.horizontal, 10)
    }

    private func row(icon: String, label: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 26)
                Text(label)
                    .font(.system(size: 15))
                Spacer()
            }
            .foregroundStyle(danger ? Self.danger : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Managed channels (DESIGN.md §9 + new channel manager)

/// Codable model used by the side drawer and the channel manager sheet.
/// Persisted as JSON in `AppStorage` so user-added channels survive
/// relaunches.
struct ManagedChannel: Identifiable, Hashable, Codable {
    var id: String { name }
    var name: String
    var hint: String
    var unread: Int
    var isDanger: Bool

    static let defaults: [ManagedChannel] = [
        ManagedChannel(name: "global", hint: "canale principale", unread: 0, isDanger: false)
    ]
}

/// Sheet opened by tapping `#mesh` in the header. Lets the user switch
/// channel, create new ones, or swipe-to-delete existing ones (`#mesh`
/// is protected as the home channel and cannot be removed).
struct ChannelManagerSheet: View {
    @Binding var channels: [ManagedChannel]
    @Binding var selectedTopic: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var draftName: String = ""
    @FocusState private var draftFocused: Bool

    private static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)
    private static let danger = Color(red: 0.753, green: 0.212, blue: 0.173)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(channels) { ch in
                        channelRow(ch)
                            .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                            .listRowBackground(
                                ch.name == selectedTopic
                                ? Self.accent.opacity(colorScheme == .dark ? 0.18 : 0.12)
                                : Color.clear
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if ch.name != "mesh" {
                                    Button(role: .destructive) {
                                        delete(ch)
                                    } label: {
                                        Label("elimina", systemImage: "trash")
                                    }
                                }
                            }
                    }
                } header: {
                    Text("canali")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack(spacing: 10) {
                        Text("#")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Self.accent)
                            .frame(width: 18)
                        TextField("nuovo canale", text: $draftName)
                            .focused($draftFocused)
                            .font(.system(size: 15))
                            .autocorrectionDisabled(true)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .submitLabel(.done)
                            .onSubmit(addChannel)
                        if canAdd {
                            Button(action: addChannel) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Self.accent)
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: canAdd)
                } header: {
                    Text("aggiungi")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("solo lettere, numeri e trattini. swipe per eliminare un canale (#mesh non puo' essere rimosso).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("canali")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
            }
        }
    }

    private func channelRow(_ ch: ManagedChannel) -> some View {
        Button {
            selectedTopic = ch.name
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text("#")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        ch.isDanger
                        ? Self.danger
                        : (ch.name == selectedTopic ? Self.accent : Color.secondary)
                    )
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ch.name)
                        .font(.system(size: 15, weight: ch.name == selectedTopic ? .semibold : .medium))
                        .foregroundStyle(Color.primary)
                    Text(ch.hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if ch.unread > 0 {
                    Text("\(ch.unread)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Self.accent, in: Capsule())
                }
                if ch.name == selectedTopic {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Self.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var canAdd: Bool {
        let t = normalizedDraft
        return !t.isEmpty && !channels.contains(where: { $0.name == t })
    }

    private var normalizedDraft: String {
        let lower = draftName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private func addChannel() {
        let name = normalizedDraft
        guard !name.isEmpty, !channels.contains(where: { $0.name == name }) else { return }
        let new = ManagedChannel(name: name, hint: "creato adesso", unread: 0, isDanger: false)
        channels.append(new)
        draftName = ""
        draftFocused = false
        selectedTopic = name
    }

    private func delete(_ ch: ManagedChannel) {
        guard ch.name != "mesh" else { return }
        channels.removeAll { $0.name == ch.name }
        if selectedTopic == ch.name {
            selectedTopic = "mesh"
        }
    }
}

// MARK: - Composer Action Tile (DESIGN.md §5)

/// Square tile shown inside the composer action drawer. Layout matches
/// the design tokens: 60pt min width, 14pt radius, surface2 background
/// (or pale-red for danger variant), 22pt icon + 10.5pt label.
struct ComposerActionTile: View {
    let icon: String
    let label: String
    var danger: Bool = false
    var showBadge: Bool = false
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .regular))
                    Text(label)
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundColor(foreground)
                .frame(minWidth: 60)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(background)
                )

                if showBadge {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(background, lineWidth: 1.5))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        if danger { return Color(red: 0.753, green: 0.212, blue: 0.173) } // #C0362C
        return colorScheme == .dark ? .white : .black
    }

    private var background: Color {
        if danger {
            // #FEE9E7 light, danger 14% alpha dark
            return colorScheme == .dark
                ? Color(red: 0.753, green: 0.212, blue: 0.173).opacity(0.18)
                : Color(red: 0.996, green: 0.913, blue: 0.906)
        }
        return colorScheme == .dark
            ? Color(red: 0.110, green: 0.110, blue: 0.122)
            : Color(red: 0.949, green: 0.945, blue: 0.925)
    }
}
