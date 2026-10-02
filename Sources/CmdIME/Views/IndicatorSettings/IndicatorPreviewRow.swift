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
    private static let controlInset: CGFloat = 7

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: AppModel
    @ObservedObject var library: IndicatorLibrary
    let isAdjusting: Bool
    /// The size and text sliders' values while they are dragged, before the model has them.
    var sizeDraft: Double?
    var textScaleDraft: Double?

    @StateObject private var state = BubbleState()
    @State private var page = Page.dark
    @State private var slotStep = 0
    @State private var previousSlot: InputRole?
    /// Set by Next slot for the one presentation it causes: that is a switch while the
    /// bubble is up, so an adaptive theme shows the row. Replays and setting changes
    /// start from hidden again and show the Mark.
    @State private var isNextSlotPending = false
    @State private var isShown = true
    @State private var bubbleWidth: CGFloat = 0
    @State private var stageWidth: CGFloat = 0

    var body: some View {
        let current = currentModel
        // The controls sit inside the stage, on the line of the sample text: the bubble starts
        // above that line, so they never cover it.
        stage(current)
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 8) {
                    if fit.scale < 1 {
                        Text("Shown at \(Int((fit.scale * 100).rounded())) percent")
                            .font(.caption)
                            .foregroundStyle((page == .dark ? Color.white : Color.black).opacity(0.62))
                    }
                    ConsoleSegmentedControl(
                        options: [ConsoleSegmentOption(value: Page.dark, label: String(localized: "Dark page")),
                                  ConsoleSegmentOption(value: Page.light, label: String(localized: "Light page"))],
                        selection: $page
                    )
                    .frame(width: 176)
                    .accessibilityLabel("Preview background")
                    Button("Next slot", action: showNextSlot)
                        .buttonStyle(ConsoleButtonStyle())
                        .disabled(model.config.slots.count < 2)
                }
                .padding(Self.controlInset)
            }
        .onAppear { if let current { present(current, replay: false) } }
        .onChange(of: current) { next in
            guard let next else { return }
            let switching = isNextSlotPending
            isNextSlotPending = false
            present(switching ? bubbleModel(occasion: .switched(whileVisible: true)) ?? next : next, replay: !isAdjusting)
        }
        .onChange(of: isAdjusting) { adjusting in
            if !adjusting, let current { present(current, replay: true) }
        }
    }

    // MARK: - Stage

    /// A bubble wider than the stage first gives up its leading inset, then is scaled
    /// down, so large Size, Scale and Text values are never shown cut off.
    private var fit: (leading: CGFloat, scale: CGFloat) {
        guard bubbleWidth > 0, stageWidth > 0 else { return (Self.bubbleLeading, 1) }
        let available = stageWidth - 2 * Self.pagePadding
        let scale = min(1, available / bubbleWidth)
        let leading = min(Self.bubbleLeading, stageWidth - Self.pagePadding - bubbleWidth * scale)
        return (max(Self.pagePadding, leading), scale)
    }

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
                    .fixedSize()
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: PreviewWidthKey.self, value: proxy.size.width)
                    })
                    .onPreferenceChange(PreviewWidthKey.self) { bubbleWidth = $0 }
                    .scaleEffect(fit.scale, anchor: .bottomLeading)
                    // Matches the live bubble, which no longer travels on the way in.
                    .opacity(isShown ? 1 : 0)
                    .padding(.leading, fit.leading)
                    .padding(.bottom, caretTop + Self.bubbleLift)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .bottomLeading)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { stageWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { stageWidth = $0 }
        })
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

    /// The bubble as it appears from hidden. Its occasion is fixed, so clearing
    /// `isNextSlotPending` never changes it and never replays the preview a second time.
    private var currentModel: BubbleRenderModel? {
        bubbleModel(occasion: .switched(whileVisible: false))
    }

    private func bubbleModel(occasion: AdaptiveBubbleLayout.Occasion) -> BubbleRenderModel? {
        previewedSlot.flatMap {
            IndicatorPreviewModel.make(
                model: model,
                slot: $0,
                previous: previousSlot,
                sizeFactor: sizeDraft,
                textScale: textScaleDraft,
                occasion: occasion
            )
        }
    }

    /// For the switcher this also plays the thumb slide from the slot shown before.
    private func showNextSlot() {
        previousSlot = previewedSlot?.id
        isNextSlotPending = true
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

private struct PreviewWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
