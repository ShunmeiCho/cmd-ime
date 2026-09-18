import KeyboardSwitcherCore
import SwiftUI

/// The real bubble view at real metrics over a sample page. It replays the appear
/// when a setting changes or when clicked; while a slider is dragged it follows the
/// value and replays once on release.
struct IndicatorPreviewRow: View {
    private enum Page: Hashable {
        case dark, light
    }

    private static let darkPage = Color(red: 0.11, green: 0.11, blue: 0.12)
    private static let lightPage = Color.white
    private static let minHeight: CGFloat = 118
    private static let pagePadding: CGFloat = 14
    private static let caretHeight: CGFloat = 16
    private static let bubbleLeading: CGFloat = 44
    private static let bubbleLift: CGFloat = 12
    private static let headroom: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: AppModel
    @ObservedObject var library: IndicatorLibrary
    let isAdjusting: Bool

    @StateObject private var state = BubbleState()
    @State private var page = Page.dark
    @State private var slotStep = 0
    @State private var previousSlot: InputRole?
    @State private var isShown = true

    var body: some View {
        let current = currentModel
        VStack(alignment: .leading, spacing: 8) {
            stage(current)
            HStack(spacing: 8) {
                ConsoleSegmentedControl(
                    options: [ConsoleSegmentOption(value: Page.dark, label: "Dark page"),
                              ConsoleSegmentOption(value: Page.light, label: "Light page")],
                    selection: $page
                )
                .frame(width: 176)
                .accessibilityLabel("Preview background")
                Spacer(minLength: 0)
                Button("Next slot", action: showNextSlot)
                    .buttonStyle(ConsoleButtonStyle())
                    .disabled(model.config.slots.count < 2)
            }
        }
        .onAppear { if let current { present(current, replay: false) } }
        .onChange(of: current) { next in
            guard let next else { return }
            present(next, replay: !isAdjusting)
        }
        .onChange(of: isAdjusting) { adjusting in
            if !adjusting, let current { present(current, replay: true) }
        }
    }

    // MARK: - Stage

    private func stage(_ current: BubbleRenderModel?) -> some View {
        let isDarkPage = page == .dark
        let ink = isDarkPage ? Color.white : Color.black
        let bubbleHeight = (current?.metrics.baseHeight ?? 0).points
        let caretTop = Self.pagePadding + Self.caretHeight
        let height = max(Self.minHeight, caretTop + Self.bubbleLift + bubbleHeight + Self.headroom)

        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                .fill(isDarkPage ? Self.darkPage : Self.lightPage)

            HStack(alignment: .center, spacing: 2) {
                Text("The quick brown fox")
                    .font(.system(size: 12))
                    .foregroundStyle(ink.opacity(0.62))
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(ink.opacity(0.86))
                    .frame(width: 1.5, height: Self.caretHeight)
            }
            .padding(Self.pagePadding)
            .accessibilityHidden(true)

            if let shown = state.model {
                SwitchBubbleView(model: shown, mode: .preview, presentation: state.presentation)
                    .opacity(isShown ? 1 : 0)
                    .offset(y: isShown || reduceMotion ? 0 : BubbleMotion.riseDistance)
                    .padding(.leading, Self.bubbleLeading)
                    .padding(.bottom, caretTop + Self.bubbleLift)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                .stroke(DesignTokens.Colors.separator, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { if let current { present(current, replay: true) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Indicator preview")
        .accessibilityHint("Replays the appear animation")
    }

    // MARK: - Model

    private var previewedSlot: SwitchSlot? {
        let slots = model.config.slots
        guard !slots.isEmpty else { return nil }
        let base = model.previewSlot.flatMap { slots.firstIndex(of: $0) } ?? 0
        return slots[(base + slotStep) % slots.count]
    }

    private var currentModel: BubbleRenderModel? {
        previewedSlot.flatMap {
            IndicatorPreviewModel.make(model: model, slot: $0, previous: previousSlot, isDark: page == .dark)
        }
    }

    /// For the switcher this also plays the thumb slide from the slot shown before.
    private func showNextSlot() {
        previousSlot = previewedSlot?.id
        slotStep += 1
    }

    private func present(_ next: BubbleRenderModel, replay: Bool) {
        state.present(next, fresh: replay, anchor: .bottomLeading, fixedSize: nil, reduceMotion: reduceMotion)
        guard replay else { return }
        var immediate = Transaction()
        immediate.disablesAnimations = true
        withTransaction(immediate) { isShown = false }
        let duration = reduceMotion ? BubbleMotion.reducedFadeIn : BubbleMotion.appearDuration
        DispatchQueue.main.async {
            withAnimation(BubbleMotion.easeOut(duration: duration)) { isShown = true }
        }
    }
}
