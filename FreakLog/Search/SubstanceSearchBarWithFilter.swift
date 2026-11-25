import SwiftUI

struct SubstanceSearchBarWithFilter: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let allCategories: [String]
    let toggleCategory: (String) -> Void
    let selectedCategories: [String]
    let clearCategories: () -> Void
    var showsFilters = true

    @Environment(\.colorScheme) var colorScheme
    private let horizontalPadding: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Search substances", text: $text)
                        .focused(isFocused)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                    if !text.isEmpty {
                        Button {
                            text = ""
                        } label: {
                            Label("Clear Search", systemImage: "xmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, text.isEmpty ? 10 : 0)
                .frame(minHeight: 44)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10))
                if showsFilters {
                    filterMenu
                }
                if isFocused.wrappedValue {
                    Button("Cancel") {
                        text = ""
                        isFocused.wrappedValue = false
                    }
                    .frame(minHeight: 44)
                }
            }
            if showsFilters, !selectedCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedCategories, id: \.self) { category in
                            Button {
                                toggleCategory(category)
                            } label: {
                                Label(category, systemImage: "xmark")
                                    .font(.subheadline)
                                    .frame(minHeight: 36)
                            }
                            .accessibilityLabel("Remove \(category) filter")
                            .buttonStyle(.bordered)
                        }
                        Button("Clear Filters", action: clearCategories)
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .animation(.default, value: isFocused.wrappedValue)
    }

    private var filterMenu: some View {
        Menu {
            ForEach(allCategories, id: \.self) { category in
                Button {
                    toggleCategory(category)
                } label: {
                    if selectedCategories.contains(category) {
                        Label(category, systemImage: "checkmark")
                    } else {
                        Text(category)
                    }
                }
            }
        } label: {
            Label("Filter Substances", systemImage: selectedCategories.isEmpty
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }

    var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(.systemGray5)
        } else {
            return Color(.systemGray6)
        }
    }
}

private struct SearchBarContainer: View {
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        SubstanceSearchBarWithFilter(
            text: .constant("d"),
            isFocused: $isSearchFocused,
            allCategories: ["psychedelic", "opioid"],
            toggleCategory: { _ in },
            selectedCategories: [],
            clearCategories: {}
        )
    }
}

#Preview {
    NavigationStack {
        VStack {
            SearchBarContainer()
            Spacer()
        }
        .navigationTitle("Substances")
    }
}
