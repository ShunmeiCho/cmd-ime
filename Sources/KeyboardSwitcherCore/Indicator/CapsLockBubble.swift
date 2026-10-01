import Foundation

extension IndicatorBubbleResolver {
    public static let capsLockOnGlyph = "A"
    public static let capsLockOffGlyph = "a"

    /// The bubble for a Caps Lock toggle: the user's theme and the colours of the slot in use
    /// (the first slot when the current source belongs to none), with the glyph and title saying
    /// what the lock did. The detail still names the input source, which Caps Lock does not change.
    ///
    /// A strip that draws every slot would put a thumb on a slot the user did not pick, so the
    /// Switcher draws as a tile and the Badge as a mark; every other archetype keeps its shape.
    public static func capsLockModel(
        isOn: Bool,
        config: SwitcherConfig,
        themes: [IndicatorTheme],
        sources: [InputSourceInfo],
        slotID: InputRole?,
        source: InputSourceInfo?,
        context: IndicatorRenderContext
    ) -> BubbleRenderModel? {
        guard let slotID = slotID.flatMap({ config.slot($0)?.id }) ?? config.slots.first?.id else { return nil }
        var theme = resolvedTheme(id: config.switchIndicatorThemeID, in: themes).theme
        theme.archetype = singleSlotArchetype(for: theme.archetype)
        var singleSlotConfig = config
        singleSlotConfig.switchIndicatorThemeID = theme.id
        guard let slotModel = model(
            config: singleSlotConfig,
            themes: [theme],
            sources: sources,
            slotID: slotID,
            previousSlotID: nil,
            source: source,
            context: context
        ) else { return nil }
        return slotModel.announcingCapsLock(isOn: isOn)
    }

    static func singleSlotArchetype(for archetype: BubbleArchetype) -> BubbleArchetype {
        switch archetype {
        case .switcher: .tileTwoLine
        case .badge: .mark
        case .tileTwoLine, .lineWithBar, .stackedText, .tileOnly, .mark: archetype
        }
    }
}

extension BubbleRenderModel {
    fileprivate func announcingCapsLock(isOn: Bool) -> BubbleRenderModel {
        BubbleRenderModel(
            themeID: themeID,
            fellBackFromThemeID: fellBackFromThemeID,
            archetype: archetype,
            display: display,
            substrate: substrate,
            symbol: SlotSymbol(glyph: isOn ? IndicatorBubbleResolver.capsLockOnGlyph : IndicatorBubbleResolver.capsLockOffGlyph),
            title: isOn ? CoreLocalization.text("Caps Lock On") : CoreLocalization.text("Caps Lock Off"),
            detail: detail,
            isRightToLeft: false,
            tileFillHex: tileFillHex,
            glyphHex: glyphHex,
            titleHex: titleHex,
            detailHex: detailHex,
            detailOpacity: detailOpacity,
            barHex: barHex,
            strokeOpacity: strokeOpacity,
            highlightStrength: highlightStrength,
            shadowStrength: shadowStrength,
            typography: typography,
            metrics: metrics,
            cells: [],
            activeIndex: 0,
            previousIndex: nil
        )
    }
}
