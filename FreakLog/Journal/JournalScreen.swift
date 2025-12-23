import SwiftUI

struct JournalScreen: View {

    @Binding var searchText: String
    @Binding var isSearchPresented: Bool
    @Binding var isFavoriteFilterEnabled: Bool

    @State private var isTimeRelative = false

    @AppStorage(PersistenceConfiguration.Keys.isEyeOpenKey2) var isEyeOpen: Bool = false
    @AppStorage(PersistenceConfiguration.Keys.fabButtonPosition) var fabButtonPositionString: String = FabButtonPosition.center.rawValue

    var fabAlignment: Alignment {
        (FabButtonPosition(rawValue: fabButtonPositionString) ?? .center).alignment
    }

    var body: some View {
        FabPosition(alignment: fabAlignment) {
            if !isSearchPresented {
                Button {
                    Navigator.shared.showAddIngestionFullScreenCover()
                } label: {
                    Label("New Ingestion", systemImage: "plus").labelStyle(FabLabelStyle())
                }
            }
        } screen: {
            ExperiencesList(
                searchText: searchText,
                isFavoriteFilterEnabled: isFavoriteFilterEnabled,
                isTimeRelative: isTimeRelative
            )
            .scrollDismissesKeyboard(.interactively)
            .modify {
                if #available(iOS 17.0, *) {
                    $0.searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search experiences")
                } else {
                    $0.searchable(text: $searchText, prompt: "Search experiences")
                }
            }
            .disableAutocorrection(true)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                favoriteButton
                Menu {
                    Button {
                        isTimeRelative = false
                    } label: {
                        let option = SaveableTimeDisplayStyle.regular
                        if isTimeRelative {
                            Text(option.text)
                        } else {
                            Label(option.text, systemImage: "checkmark")
                        }
                    }
                    Button {
                        isTimeRelative = true
                    } label: {
                        let option = SaveableTimeDisplayStyle.relativeToNow
                        if isTimeRelative {
                            Label(option.text, systemImage: "checkmark")
                        } else {
                            Text(option.text)
                        }
                    }
                } label: {
                    Label("Time Display", systemImage: "timer")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(value: GlobalNavigationDestination.calendar) {
                    Label("Calendar", systemImage: "calendar")
                }
            }
        }
        .navigationTitle("Journal")
    }

    private var favoriteButton: some View {
        Button {
            isFavoriteFilterEnabled.toggle()
        } label: {
            if isFavoriteFilterEnabled {
                Label("Don't Filter Favorites", systemImage: "star.fill")
            } else {
                Label("Filter Favorites", systemImage: "star")
            }
        }
    }
}

extension View {
    func modify<Content>(@ViewBuilder _ transform: (Self) -> Content) -> Content {
        transform(self)
    }
}
