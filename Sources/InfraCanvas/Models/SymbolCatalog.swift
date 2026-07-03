import AppKit
import SwiftUI

enum SymbolCatalog {
    static let fallbackSymbolName = "square.stack.3d.up"

    static func resolvedName(_ preferredName: String) -> String {
        isAvailable(preferredName) ? preferredName : fallbackSymbolName
    }

    static func image(named preferredName: String, accessibilityDescription: String? = nil) -> NSImage? {
        NSImage(
            systemSymbolName: resolvedName(preferredName),
            accessibilityDescription: accessibilityDescription
        )
    }

    static func unavailableNames(in names: some Sequence<String>) -> [String] {
        Array(Set(names.filter { !isAvailable($0) })).sorted()
    }

    static func isAvailable(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}

struct SafeSymbolImage: View {
    var name: String

    var body: some View {
        Image(systemName: SymbolCatalog.resolvedName(name))
            .accessibilityLabel(SymbolCatalog.resolvedName(name))
    }
}
