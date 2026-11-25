import SwiftUI

struct SubstanceSearchBarWithFilter: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let allCategories: [String]
    let toggleCategory: (String) -> Void
    let selectedCategories: [String]
    let clearCategories: () -> Void
    var showsFilters = true
    var personalTags: [String] = []
    var selectedPersonalTag: Binding<String?> = .constant(nil)

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
            if showsFilters, !selectedCategories.isEmpty || selectedPersonalTag.wrappedValue != nil {
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
                        if let tag = selectedPersonalTag.wrappedValue {
                            Button {
                                selectedPersonalTag.wrappedValue = nil
                            } label: {
                                Label(tag, systemImage: "xmark")
                                    .font(.subheadline)
                                    .frame(minHeight: 36)
                            }
                            .accessibilityLabel("Remove \(tag) tag filter")
                            .buttonStyle(.bordered)
                        }
                        Button("Clear Filters") {
                            clearCategories()
                            selectedPersonalTag.wrappedValue = nil
                        }
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
            Section("Categories") {
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
            }
            if !personalTags.isEmpty {
                Section("Personal Tags") {
                    Picker("Personal Tag", selection: selectedPersonalTag) {
                        Text("All Tags").tag(nil as String?)
                        ForEach(personalTags, id: \.self) { tag in
                            Text(tag).tag(Optional(tag))
                        }
                    }
                }
            }
        } label: {
            Label("Filter Substances", systemImage: selectedCategories.isEmpty && selectedPersonalTag.wrappedValue == nil
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
