import AppKit
import KeyboardSwitcherCore
import SwiftUI

struct InputSourcePresentation {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color

    init(source: InputSourceInfo?, slot: SwitchSlot) {
        tint = Color(cmdIMEHex: slot.tintHex) ?? CmdIMEDesign.Colors.role(slot.id)
        guard let source else {
            symbol = slot.id.defaultSymbol
            title = switch slot.id {
            case .english: String(localized: "English")
            case .chinese: String(localized: "中文")
            case .japanese: String(localized: "日本語")
            default: slot.name
            }
            detail = String(localized: "No input method selected")
            return
        }

        let sourceKind = InputSourceKind(source: source)
        symbol = sourceKind.symbol(source: source)
        title = sourceKind.title(fallback: slot.name)
        detail = source.localizedName
    }

}
