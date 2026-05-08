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

            Divider()

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

            HStack(alignment: .center, spacing: 10) {
                TextField(
                    "",
                    text: $messageText,
                    prompt: Text(
                        String(localized: "content.input.message_placeholder", comment: "Placeholder shown in the chat composer")
                    )
                    .foregroundColor(secondaryTextColor.opacity(0.55))
                )
                .textFieldStyle(.plain)
                .font(.bitchatSystem(size: 15, design: .monospaced))
                .foregroundColor(textColor)
                .focused($isTextFieldFocused)
                .autocorrectionDisabled(true)
#if os(iOS)
                .textInputAutocapitalization(.sentences)
#endif
                .submitLabel(.send)
                .onSubmit { sendMessage() }
                .modifier(FocusEffectDisabledModifier())
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: messageText) { newValue in
                    autocompleteDebounceTimer?.invalidate()
                    autocompleteDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak viewModel] _ in
                        let cursorPosition = newValue.count
                        Task { @MainActor in
                            viewModel?.updateAutocomplete(for: newValue, cursorPosition: cursorPosition)
                        }
                    }
                }

                HStack(alignment: .center, spacing: 14) {
                    SOSMapButton(viewModel: viewModel)
                    RadarButton(viewModel: viewModel)
                    SOSButton(viewModel: viewModel)
                    if shouldShowMediaControls {
                        attachmentButton
                    }
                    sendOrMicButton
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.95))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(secondaryTextColor.opacity(0.18), lineWidth: 1)
            )
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(backgroundColor.opacity(0.95))
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
        HStack(spacing: 6) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(textColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings menu")

            Text(verbatim: "meshcomm/")
                .font(.bitchatSystem(size: 18, weight: .medium, design: .monospaced))
                .foregroundColor(textColor)
                .onTapGesture(count: 3) {
                    // PANIC: Triple-tap to clear all data
                    viewModel.panicClearAllData()
                }
                .onTapGesture(count: 1) {
                    // Single tap for app info
                    showAppInfo = true
                }
            
            HStack(spacing: 0) {
                Text(verbatim: "@")
                    .font(.bitchatSystem(size: 14, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
                
                TextField("content.input.nickname_placeholder", text: $viewModel.nickname)
                    .textFieldStyle(.plain)
                    .font(.bitchatSystem(size: 14, design: .monospaced))
                    .frame(maxWidth: 80)
                    .foregroundColor(textColor)
                    .focused($isNicknameFieldFocused)
                    .autocorrectionDisabled(true)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .modifier(FocusEffectDisabledModifier())
                    .onChange(of: isNicknameFieldFocused) { isFocused in
                        if !isFocused {
                            // Only validate when losing focus
                            viewModel.validateAndSaveNickname()
                        }
                    }
                    .onSubmit {
                        viewModel.validateAndSaveNickname()
                    }
            }
            
            Spacer()
            
            // Channel badge + dynamic spacing + people counter
            // Precompute header count and color outside the ViewBuilder expressions
            let cc = channelPeopleCountAndColor()
            let headerCountColor: Color = cc.1
            let headerOtherPeersCount: Int = {
                if case .location = locationManager.selectedChannel {
                    return viewModel.visibleGeohashPeople().count
                }
                return cc.0
            }()

            HStack(spacing: 10) {
                // Unread icon immediately to the left of the channel badge (independent from channel button)
                
                // Unread indicator (now shown on iOS and macOS)
                if viewModel.hasAnyUnreadMessages {
                    Button(action: { viewModel.openMostRelevantPrivateChat() }) {
                        Image(systemName: "envelope.fill")
                            .font(.bitchatSystem(size: 12))
                            .foregroundColor(Color.orange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String(localized: "content.accessibility.open_unread_private_chat", comment: "Accessibility label for the unread private chat button")
                    )
                }
                // Notes icon (mesh only and when location is authorized), to the left of #mesh
                if case .mesh = locationManager.selectedChannel, locationManager.permissionState == .authorized {
                    Button(action: {
                        // Kick a one-shot refresh and show the sheet immediately.
                        LocationChannelManager.shared.enableLocationChannels()
                        LocationChannelManager.shared.refreshChannels()
                        // If we already have a block geohash, pass it; otherwise wait in the sheet.
                        notesGeohash = LocationChannelManager.shared.availableChannels.first(where: { $0.level == .building })?.geohash
                        showLocationNotes = true
                    }) {
                        HStack(alignment: .center, spacing: 4) {
                            Image(systemName: "note.text")
                                .font(.bitchatSystem(size: 12))
                                .foregroundColor(Color.orange.opacity(0.8))
                                .padding(.top, 1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String(localized: "content.accessibility.location_notes", comment: "Accessibility label for location notes button")
                    )
                }

                // Bookmark toggle (geochats): to the left of #geohash
                if case .location(let ch) = locationManager.selectedChannel {
                    Button(action: { bookmarks.toggle(ch.geohash) }) {
                        Image(systemName: bookmarks.isBookmarked(ch.geohash) ? "bookmark.fill" : "bookmark")
                            .font(.bitchatSystem(size: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String(
                            format: String(localized: "content.accessibility.toggle_bookmark", comment: "Accessibility label for toggling a geohash bookmark"),
                            locale: .current,
                            ch.geohash
                        )
                    )
                }

                // Location channels button '#'
                Button(action: { showLocationChannelsSheet = true }) {
                    let badgeText: String = {
                        switch locationManager.selectedChannel {
                        case .mesh: return "#mesh"
                        case .location(let ch): return "#\(ch.geohash)"
                        }
                    }()
                    let badgeColor: Color = {
                        switch locationManager.selectedChannel {
                        case .mesh:
                            return Color(hue: 0.60, saturation: 0.85, brightness: 0.82)
                        case .location:
                            return (colorScheme == .dark) ? Color(red: 0.851, green: 0.467, blue: 0.341) : Color(red: 0.722, green: 0.351, blue: 0.231)
                        }
                    }()
                    Text(badgeText)
                        .font(.bitchatSystem(size: 14, design: .monospaced))
                        .foregroundColor(badgeColor)
                        .lineLimit(headerLineLimit)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                        .accessibilityLabel(
                            String(localized: "content.accessibility.location_channels", comment: "Accessibility label for the location channels button")
                        )
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
                .padding(.trailing, 2)

                HStack(spacing: 4) {
                    // People icon with count
                    Image(systemName: "person.2.fill")
                        .font(.system(size: headerPeerIconSize, weight: .regular))
                        .accessibilityLabel(
                            String(
                                format: String(localized: "content.accessibility.people_count", comment: "Accessibility label announcing number of people in header"),
                                locale: .current,
                                headerOtherPeersCount
                            )
                        )
                    Text("\(headerOtherPeersCount)")
                        .font(.system(size: headerPeerCountFontSize, weight: .regular, design: .monospaced))
                        .accessibilityHidden(true)
                }
                .foregroundColor(headerCountColor)
                .padding(.leading, 2)
                .lineLimit(headerLineLimit)
                .fixedSize(horizontal: true, vertical: false)

                // QR moved to the PEOPLE header in the sidebar when on mesh channel
            }
            .layoutPriority(3)
            .onTapGesture {
                withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                    showSidebar.toggle()
                }
            }
            .sheet(isPresented: $showVerifySheet) {
                VerificationSheetView(isPresented: $showVerifySheet)
                    .environmentObject(viewModel)
            }
        }
        .frame(height: headerHeight)
        .padding(.horizontal, 12)
        .sheet(isPresented: $showLocationChannelsSheet) {
            LocationChannelsSheet(isPresented: $showLocationChannelsSheet)
                .environmentObject(viewModel)
                .onAppear { viewModel.isLocationChannelsSheetPresented = true }
                .onDisappear { viewModel.isLocationChannelsSheetPresented = false }
        }
        .sheet(isPresented: $showLocationNotes, onDismiss: {
            notesGeohash = nil
        }) {
            Group {
                if let gh = notesGeohash ?? LocationChannelManager.shared.availableChannels.first(where: { $0.level == .building })?.geohash {
                    LocationNotesView(geohash: gh)
                        .environmentObject(viewModel)
                } else {
                    VStack(spacing: 12) {
                        HStack {
                            Text("content.notes.title")
                                .font(.bitchatSystem(size: 16, weight: .bold, design: .monospaced))
                            Spacer()
                            Button(action: { showLocationNotes = false }) {
                                Image(systemName: "xmark")
                                    .font(.bitchatSystem(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(textColor)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "common.close", comment: "Accessibility label for close buttons"))
                        }
                        .frame(height: headerHeight)
                        .padding(.horizontal, 12)
                        .background(backgroundColor.opacity(0.95))
                        Text("content.notes.location_unavailable")
                            .font(.bitchatSystem(size: 14, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                        Button("content.location.enable") {
                            LocationChannelManager.shared.enableLocationChannels()
                            LocationChannelManager.shared.refreshChannels()
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                    .background(backgroundColor)
                    .foregroundColor(textColor)
                    // per-sheet global onChange added below
                }
            }
            .onAppear {
                // Ensure we are authorized and start live location updates (distance-filtered)
                LocationChannelManager.shared.enableLocationChannels()
                LocationChannelManager.shared.beginLiveRefresh()
            }
            .onDisappear {
                LocationChannelManager.shared.endLiveRefresh()
            }
            .onChange(of: locationManager.availableChannels) { channels in
                if let current = channels.first(where: { $0.level == .building })?.geohash,
                    notesGeohash != current {
                    notesGeohash = current
                    #if os(iOS)
                    // Light taptic when geohash changes while the sheet is open
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    #endif
                }
            }
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
        .alert("content.alert.screenshot.title", isPresented: $viewModel.showScreenshotPrivacyWarning) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("content.alert.screenshot.message")
        }
        .background(backgroundColor.opacity(0.95))
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
        Image(systemName: "camera.circle.fill")
            .font(.bitchatSystem(size: 24))
            .foregroundColor(composerAccentColor)
            .frame(width: 26, height: 26)
            .contentShape(Circle())
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
            Image(systemName: "photo.circle.fill")
                .font(.bitchatSystem(size: 24))
                .foregroundColor(composerAccentColor)
                .frame(width: 26, height: 26)
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
            .frame(width: 26, height: 26)
        } else {
            sendButtonView(enabled: hasText)
                .frame(width: 26, height: 26)
        }
    }

    private var micButtonView: some View {
        Image(systemName: "mic.circle.fill")
            .font(.bitchatSystem(size: 24))
            .foregroundColor(voiceRecordingVM.state.isActive ? Color.red : composerAccentColor)
            .frame(width: 26, height: 26)
            .contentShape(Circle())
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
            Image(systemName: "paperplane.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(enabled ? activeColor : Color.gray.opacity(0.5))
                .frame(width: 26, height: 26)
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
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Color.red)
                .frame(width: 26, height: 26)
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
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(
                    viewModel.sosPins.isEmpty
                    ? Color.secondary
                    : Color(red: 0.851, green: 0.467, blue: 0.341)
                )
                .frame(width: 26, height: 26)
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
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color(red: 0.851, green: 0.467, blue: 0.341))
                .frame(width: 26, height: 26)
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

    private let accent = Color(red: 0.851, green: 0.467, blue: 0.341)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(accent)
                        TextField("callsign", text: $draftNickname)
                            .font(.system(size: 16, design: .monospaced))
                            .autocorrectionDisabled(true)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .onSubmit { saveNickname() }
                        Button("save") { saveNickname() }
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(canSave ? accent : .secondary)
                            .disabled(!canSave)
                    }
                    if savedToast {
                        Label("nickname salvato", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(red: 0.529, green: 0.682, blue: 0.420))
                    }
                } header: {
                    Label("identity", systemImage: "person.text.rectangle")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("// callsign annunciato sui pacchetti HELLO. Visibile a tutti i peer.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Section {
                    NavigationLink {
                        SOSMapView(pins: viewModel.sosPins)
                    } label: {
                        Label {
                            HStack {
                                Text("SOS map")
                                    .font(.system(size: 14, design: .monospaced))
                                Spacer()
                                Text("\(viewModel.sosPins.count)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "map")
                                .foregroundStyle(accent)
                        }
                    }
                    NavigationLink {
                        RadarSheetView(viewModel: viewModel)
                    } label: {
                        Label {
                            Text("proximity radar")
                                .font(.system(size: 14, design: .monospaced))
                        } icon: {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundStyle(accent)
                        }
                    }
                } header: {
                    Label("tools", systemImage: "wrench.and.screwdriver")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Section {
                    Label {
                        Text("meshcomm v1.0")
                            .font(.system(size: 14, design: .monospaced))
                    } icon: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(accent)
                    }
                    Label {
                        Text("Fork of bitchat (Unlicense)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://github.com/edoardomartinelli-parkpass/meshcomm")!) {
                        Label {
                            Text("github / source")
                                .font(.system(size: 13, design: .monospaced))
                        } icon: {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .foregroundStyle(accent)
                        }
                    }
                } header: {
                    Label("about", systemImage: "info.circle")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(role: .destructive) {
                        viewModel.panicClearAllData()
                        dismiss()
                    } label: {
                        Label {
                            Text("emergency wipe")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                } header: {
                    Label("danger zone", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.760, green: 0.330, blue: 0.314))
                } footer: {
                    Text("// cancella keypair, cronologia chat e pin SOS. Irreversibile.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                }
            }
            .onAppear {
                draftNickname = viewModel.nickname
            }
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
