import KeyboardSwitcherCore

extension AppModel {
    var indicatorLibrary: IndicatorLibrary { switchIndicator.library }

    /// Nil selects the default built-in theme.
    func setSwitchIndicatorThemeID(_ id: String?) {
        config.switchIndicatorThemeID = id
        save()
        statusText = "Switch indicator theme set to \(indicatorLibrary.theme(id: id).name)"
    }

    /// Sets or clears (nil or blank) a slot's symbol override. Returns the message to
    /// show beside the field when the symbol is not acceptable.
    func setSlotSymbol(_ symbol: String?, for id: InputRole) -> String? {
        do {
            config = try config.settingSlotSymbol(symbol, for: id)
            save()
            statusText = "Updated symbol for \(config.displayName(for: id))"
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Applies an appearance change to the selected theme. Built-in themes are
    /// read-only, so the first change makes a copy, selects it and edits that.
    func editIndicatorTheme(_ change: (inout IndicatorTheme) -> Void) {
        let library = indicatorLibrary
        let selected = library.theme(id: config.switchIndicatorThemeID)
        if selected.isBuiltIn {
            guard let copy = library.duplicate(selected, applying: change) else { return }
            setSwitchIndicatorThemeID(copy.id)
        } else {
            var edited = selected
            change(&edited)
            library.save(edited)
        }
    }
}
