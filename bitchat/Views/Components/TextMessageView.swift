//
// TextMessageView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
import BitFoundation

/// Telegram/WhatsApp-style chat bubble. Outgoing messages are right-aligned
/// in an orange-tinted bubble, incoming messages are left-aligned with the
/// sender label on top in a per-nickname stable hue. SOS broadcasts get a
/// red emergency frame regardless of direction.
struct TextMessageView: View {
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @EnvironmentObject private var viewModel: ChatViewModel

    let message: BitchatMessage
    @State private var expandedMessageIDs: Set<String> = []

    private static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)

    private var isOwnMessage: Bool {
        message.sender == viewModel.nickname
    }

    private var isSOS: Bool {
        message.content.hasPrefix("[SOS]")
    }

    private var bubbleFill: Color {
        if isSOS { return Color.red.opacity(0.18) }
        if isOwnMessage { return Self.accent.opacity(colorScheme == .dark ? 0.22 : 0.18) }
        return colorScheme == .dark ? Color(white: 0.13) : Color(white: 0.93)
    }

    private var bubbleBorder: Color {
        if isSOS { return Color.red.opacity(0.7) }
        if isOwnMessage { return Self.accent.opacity(0.55) }
        return colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.78)
    }

    private var senderColor: Color {
        if isOwnMessage { return Self.accent }
        let hash = abs(message.sender.hashValue)
        let hue = Double(hash % 360) / 360.0
        return colorScheme == .dark
            ? Color(hue: hue, saturation: 0.45, brightness: 0.92)
            : Color(hue: hue, saturation: 0.65, brightness: 0.55)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isOwnMessage { Spacer(minLength: 48) }

            bubble
                .frame(maxWidth: 320, alignment: isOwnMessage ? .trailing : .leading)

            if !isOwnMessage { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 1)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isSOS {
                sosHeader
            } else if !isOwnMessage {
                Text(message.sender)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(senderColor)
            }

            content

            if isLong {
                expandButton
            }

            paymentChips

            footer
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(bubbleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(bubbleBorder, lineWidth: 1)
        )
    }

    private var sosHeader: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.red)
            Text("SOS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.red)
            Text(message.sender)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private var content: some View {
        let isExpanded = expandedMessageIDs.contains(message.id)
        let lineLimit: Int? = (isLong && !isExpanded) ? TransportConfig.uiLongMessageLineLimit : nil
        return Text(message.content)
            .font(.system(size: 14, design: .monospaced))
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .foregroundStyle(.primary)
    }

    private var expandButton: some View {
        let isExpanded = expandedMessageIDs.contains(message.id)
        let labelKey = isExpanded
            ? LocalizedStringKey("content.message.show_less")
            : LocalizedStringKey("content.message.show_more")
        return Button(labelKey) {
            if isExpanded { expandedMessageIDs.remove(message.id) }
            else { expandedMessageIDs.insert(message.id) }
        }
        .font(.bitchatSystem(size: 11, weight: .medium, design: .monospaced))
        .foregroundColor(Self.accent)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var paymentChips: some View {
        let lightningLinks = message.content.extractLightningLinks()
        let cashuLinks = message.content.extractCashuLinks()
        if !lightningLinks.isEmpty || !cashuLinks.isEmpty {
            HStack(spacing: 8) {
                ForEach(lightningLinks, id: \.self) { link in
                    PaymentChipView(paymentType: .lightning(link))
                }
                ForEach(cashuLinks, id: \.self) { link in
                    PaymentChipView(paymentType: .cashu(link))
                }
            }
            .padding(.top, 4)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(message.formattedTimestamp)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            if message.isPrivate && isOwnMessage,
               let status = message.deliveryStatus {
                DeliveryStatusView(status: status)
            }
        }
    }

    private var isLong: Bool {
        let cashu = message.content.extractCashuLinks()
        return (message.content.count > TransportConfig.uiLongMessageLengthThreshold
                || message.content.hasVeryLongToken(threshold: TransportConfig.uiVeryLongTokenThreshold))
            && cashu.isEmpty
    }
}

#Preview {
    let keychain = PreviewKeychainManager()

    Group {
        List {
            TextMessageView(message: .preview)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(EmptyView())
        }
        .environment(\.colorScheme, .dark)

        List {
            TextMessageView(message: .preview)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(EmptyView())
        }
        .environment(\.colorScheme, .light)
    }
    .environmentObject(
        ChatViewModel(
            keychain: keychain,
            idBridge: NostrIdentityBridge(),
            identityManager: SecureIdentityStateManager(keychain)
        )
    )
}
