import SwiftUI
import WrappingHStack

struct CategorySection: View {
    let substance: Substance
    @State private var categories: [Category] = []

    @State private var isAlertShown = false
    @State private var title = ""
    @State private var message = ""
    @State private var articleURL: URL?

    private func showAlert(title: String, message: String, articleURL: URL?) {
        isAlertShown = true
        self.title = title
        self.message = message
        self.articleURL = articleURL
    }

    var body: some View {
        WrappingHStack(
            alignment: .leading,
            horizontalSpacing: 3,
            verticalSpacing: 3
        ) {
            ForEach(categories, id: \.name) { category in
                Button(category.name.localizedCapitalized) {
                    showAlert(title: category.name.localizedCapitalized, message: category.description, articleURL: category.url)
                }.buttonStyle(.bordered)
            }
        }
        .alert(title, isPresented: $isAlertShown, actions: {
            if let articleURL {
                NavigationLink(value: GlobalNavigationDestination.webView(articleURL: articleURL)) {
                    Label("Article", systemImage: "link")
                }
            }
            Button("Ok") {
                isAlertShown = false
            }
        }, message: {
            Text(message)
        })
        .onAppear {
            categories = substance.categories.compactMap { name in
                SubstanceRepo.shared.categories.first(where: { cat in
                    cat.name == name
                })
            }
        }
    }
}

#Preview {
    CategorySection(substance: SubstanceRepo.shared.getSubstance(name: "MDMA")!)
}
