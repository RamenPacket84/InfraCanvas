import SwiftUI

struct ComponentPaletteView: View {
    @EnvironmentObject private var boardStore: BoardStore
    @State private var searchText = ""
    @State private var selectedCategory: ComponentCategory?

    private var groupedTemplates: [(ComponentCategory, [ComponentTemplate])] {
        ComponentCategory.allCases.map { category in
            (category, filteredTemplates.filter { $0.category == category })
        }
        .filter { !$0.1.isEmpty }
    }

    private var filteredTemplates: [ComponentTemplate] {
        ComponentTemplate.library.filter { template in
            let matchesCategory = selectedCategory == nil || template.category == selectedCategory
            let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesSearch = trimmedSearch.isEmpty || template.searchText.contains(trimmedSearch)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        List {
            Section {
                Text(boardStore.board.name)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(boardStore.board.nodes.count) components")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Catalog") {
                Picker("Category", selection: $selectedCategory) {
                    Text("All Components")
                        .tag(ComponentCategory?.none)

                    ForEach(ComponentCategory.allCases) { category in
                        Text(category.rawValue)
                            .tag(ComponentCategory?.some(category))
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Label(ComponentTemplate.library.count.formatted(), systemImage: "square.grid.2x2")
                    Spacer()
                    Text("templates")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            ForEach(groupedTemplates, id: \.0.id) { category, templates in
                Section("\(category.rawValue) (\(templates.count))") {
                    ForEach(templates) { template in
                        Button {
                            boardStore.addNode(from: template)
                        } label: {
                            PaletteRow(template: template)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if filteredTemplates.isEmpty {
                ContentUnavailableView(
                    "No Components",
                    systemImage: "magnifyingglass",
                    description: Text("Try another search or category.")
                )
            }
        }
        .navigationTitle("Components")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search components")
    }
}

private struct PaletteRow: View {
    var template: ComponentTemplate

    var body: some View {
        HStack(spacing: 10) {
            SafeSymbolImage(name: template.symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(template.tint.color)
                .frame(width: 28, height: 28)
                .background(template.tint.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(template.title)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Text(template.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
