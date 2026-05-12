//
// TextMessageView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
import BitFoundation

/// Telegram/WhatsApp-style chat bubble matching the design tokens in
/// `DESIGN.md`. Outgoing bubbles are accent-fill with white text and right
/// aligned; incoming bubbles are `surface2` with primary text and left
/// aligned. SOS broadcasts get a red emergency frame regardless of direction.
struct TextMessageView: View {
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @EnvironmentObject private var viewModel: ChatViewModel

    let message: BitchatMessage
    @State private var expandedMessageIDs: Set<String> = []

    private static let accent = Color(red: 0.851, green: 0.467, blue: 0.341) // #D97757

    private var isOwnMessage: Bool {
        message.sender == viewModel.nickname
    }

    private var isSOS: Bool {
        message.content.hasPrefix("[SOS]")
    }

    private var incomingBg: Color {
        // #F1EFEA light, #1A1A1D dark
        colorScheme == .dark
            ? Color(red: 0.102, green: 0.102, blue: 0.114)
            : Color(red: 0.945, green: 0.937, blue: 0.918)
    }

    private var bubbleFill: Color {
        if isSOS { return Color(red: 0.753, green: 0.212, blue: 0.173).opacity(0.14) }
        return isOwnMessage ? Self.accent : incomingBg
    }

    private var bubbleText: Color {
        if isSOS { return Color(red: 0.753, green: 0.212, blue: 0.173) }
        return isOwnMessage ? .white : .primary
    }

    private var senderColor: Color {
        if isOwnMessage { return Self.accent }
        let hash = abs(message.sender.hashValue)
        let hue = Double(hash % 360) / 360.0
        return colorScheme == .dark
            ? Color(hue: hue, saturation: 0.45, brightness: 0.92)
            : Color(hue: hue, saturation: 0.55, brightness: 0.50)
    }

    private var faint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.32)
            : Color.black.opacity(0.32)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isOwnMessage { Spacer(minLength: 60) }

            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 3) {
                if !isOwnMessage && !isSOS {
                    Text(message.sender)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(senderColor)
                        .padding(.leading, 4)
                }

                bubble

                footer
            }

            if !isOwnMessage { Spacer(minLength: 60) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isSOS {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.octagon")
                        .font(.system(size: 13, weight: .regular))
                    Text("SOS")
                        .font(.system(size: 11, weight: .bold))
                    Text(message.sender)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color(red: 0.753, green: 0.212, blue: 0.173))
            }

            content

            if isLong {
                expandButton
            }

            paymentChips
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            bubbleFill,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            Group {
                if isSOS {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(red: 0.753, green: 0.212, blue: 0.173).opacity(0.6), lineWidth: 1)
                }
            }
        )
    }

    private var content: some View {
        let isExpanded = expandedMessageIDs.contains(message.id)
        let lineLimit: Int? = (isLong && !isExpanded) ? TransportConfig.uiLongMessageLineLimit : nil
        return Text(message.content)
            .font(.system(size: 15))
            .lineSpacing(2)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .foregroundStyle(bubbleText)
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
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(isOwnMessage ? .white.opacity(0.85) : Self.accent)
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
            Text(message.formattedTimestamp)
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(faint)
            if message.isPrivate && isOwnMessage,
               let status = message.deliveryStatus {
                DeliveryStatusView(status: status)
            }
        }
        .padding(.horizontal, 6)
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
