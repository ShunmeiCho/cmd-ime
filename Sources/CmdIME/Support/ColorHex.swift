import AppKit
import SwiftUI

extension Color {
    init?(cmdIMEHex string: String) {
        var value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        guard value.count == 6, let integer = Int(value, radix: 16) else {
            return nil
        }

        let red = Double((integer >> 16) & 0xff) / 255.0
        let green = Double((integer >> 8) & 0xff) / 255.0
        let blue = Double(integer & 0xff) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }

    var cmdIMEHexString: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else {
            return nil
        }

        let red = Int((color.redComponent * 255.0).rounded())
        let green = Int((color.greenComponent * 255.0).rounded())
        let blue = Int((color.blueComponent * 255.0).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
