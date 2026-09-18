import AppKit
import KeyboardSwitcherCore
import SwiftUI
import UniformTypeIdentifiers

/// Imported font files. They are copied into the fonts folder beside the config
/// file and registered for this process only; nothing is installed system-wide.
struct IndicatorFontsRow: View {
    @ObservedObject var library: IndicatorLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Fonts")
                    .font(DesignTokens.Typography.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                Button("Import Font...", action: importFonts)
                    .buttonStyle(ConsoleButtonStyle())
                Button("Show in Finder") { library.revealInFinder(library.fontsDirectory) }
                    .buttonStyle(ConsoleButtonStyle())
            }

            if library.fonts.isEmpty {
                Text("No imported fonts. Imported fonts are used by CmdIME only.")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            }
            ForEach(library.fonts) { entry in
                row(for: entry)
            }
        }
    }

    private func row(for entry: IndicatorFontRegistrar.Entry) -> some View {
        let users = entry.families.flatMap(library.themeNames(using:))
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.font.fileName)
                    .font(DesignTokens.Typography.auxiliary.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if entry.isLoaded {
                    Text(entry.families.joined(separator: ", ") + (users.isEmpty ? "" : " - used by \(users.joined(separator: ", "))"))
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                        .lineLimit(2)
                } else {
                    IndicatorNotice(text: "Could not be loaded")
                }
            }
            Spacer(minLength: 0)
            Button("Remove", role: .destructive) { library.removeFont(entry) }
                .buttonStyle(ConsoleButtonStyle())
                .accessibilityLabel("Remove \(entry.font.fileName)")
        }
    }

    private func importFonts() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = FontStore.allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.message = "Fonts are copied into CmdIME's fonts folder and used by CmdIME only."
        guard panel.runModal() == .OK else { return }
        library.importFonts(from: panel.urls)
    }
}
