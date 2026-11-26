import CoreData
import SwiftUI

extension JournalPresetProduct {
    var object: NSManagedObject {
        switch self {
        case .customUnit(let unit): unit
        case .formulation(let formulation): formulation
        }
    }

    var isAvailableForLogging: Bool {
        guard !object.isDeleted, object.managedObjectContext != nil else { return false }
        switch self {
        case .customUnit(let unit): return !unit.isArchived
        case .formulation(let formulation): return !formulation.componentsSorted.isEmpty
        }
    }

    fileprivate var relationshipKey: String {
        switch self {
        case .customUnit: "customUnit"
        case .formulation: "formulation"
        }
    }
}

extension StockContainer {
    var inventoryProduct: JournalPresetProduct? {
        if let customUnit { return .customUnit(customUnit) }
        return formulation.map(JournalPresetProduct.formulation)
    }
}

struct SavedProductRow: View {
    let product: JournalPresetProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(product.name).foregroundStyle(.primary)
            Text(product.pickerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SavedProductPicker: View {
    @Binding var selection: NSManagedObjectID?
    let emptyTitle: LocalizedStringKey

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @FetchRequest(fetchRequest: PersistenceController.activeCustomUnitsRequest())
    private var customUnits: FetchedResults<CustomUnit>
    @FetchRequest(fetchRequest: PersistenceController.formulationsRequest())
    private var formulations: FetchedResults<Formulation>

    private var products: [JournalPresetProduct] {
        let all = customUnits.map(JournalPresetProduct.customUnit) + formulations.map(JournalPresetProduct.formulation)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { product in
            product.isAvailableForLogging && (query.isEmpty || (product.name + " " + product.pickerSubtitle).localizedStandardContains(query))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                choice(nil) { Text(emptyTitle) }
            }
            Section {
                if products.isEmpty {
                    Text(searchText.isEmpty ? "No saved products" : "No matching products").foregroundStyle(.secondary)
                }
                ForEach(products, id: \.object.objectID) { product in
                    choice(product.object.objectID) { SavedProductRow(product: product) }
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Product, substance, or unit")
        .navigationTitle("Choose Product")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choice<Row: View>(_ id: NSManagedObjectID?, @ViewBuilder row: () -> Row) -> some View {
        Button {
            selection = id
            dismiss()
        } label: {
            HStack {
                row()
                Spacer()
                if selection == id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selection == id ? .isSelected : [])
    }
}

private extension JournalPresetProduct {
    var pickerSubtitle: String {
        switch self {
        case .customUnit(let unit):
            String(localized: "Custom Unit · \(unit.substanceNameUnwrapped) · \(unit.doseOfOneUnitDescription) per \(unit.unitUnwrapped)")
        case .formulation(let formulation):
            String(localized: "Formulation · \(formulation.componentsDescription) per serving")
        }
    }
}

struct ProductDetailScreen: View {
    let product: JournalPresetProduct
    let allowsLogging: Bool

    @ObservedObject private var productObject: NSManagedObject
    @ObservedObject private var routines = RoutineSchedules.shared
    @FetchRequest private var containers: FetchedResults<StockContainer>
    @FetchRequest private var routineRecords: FetchedResults<RoutineRecord>
    @EnvironmentObject private var authenticator: Authenticator
    @State private var editor: Editor?
    @State private var choosingRestockContainer = false
    @State private var logging = false
    @State private var savedPackageCodes: [PharmacyPackageCode] = []
    @State private var packageToForget: PharmacyPackageCode?

    init(product: JournalPresetProduct, allowsLogging: Bool = true) {
        self.product = product
        self.allowsLogging = allowsLogging
        _productObject = ObservedObject(wrappedValue: product.object)

        let predicate = NSPredicate(format: "%K == %@", product.relationshipKey, product.object)
        let stock = StockContainer.allRequest()
        stock.predicate = predicate
        _containers = FetchRequest(fetchRequest: stock, animation: .default)
        let relatedRoutines = RoutineRecord.fetchRequest()
        relatedRoutines.predicate = predicate
        relatedRoutines.sortDescriptors = []
        _routineRecords = FetchRequest(fetchRequest: relatedRoutines, animation: .default)
    }

    private enum Editor: Identifiable {
        case container
        case restock(StockContainer)
        case routine(RoutineSchedule, isNew: Bool)
        case customUnit(CustomUnit)
        case formulation(Formulation)

        var id: AnyHashable {
            switch self {
            case .container: AnyHashable("container")
            case .restock(let container): AnyHashable(container.objectID)
            case .routine(let schedule, _): AnyHashable(schedule.id)
            case .customUnit(let unit): AnyHashable(unit.objectID)
            case .formulation(let formulation): AnyHashable(formulation.objectID)
            }
        }
    }

    var body: some View {
        List {
            if productObject.isDeleted || productObject.managedObjectContext == nil {
                Text("This product is unavailable.").foregroundStyle(.secondary)
            } else {
                definition
                savedPackages
                actions
                stock
                schedule
            }
        }
        .navigationTitle(productObject.isDeleted ? "Product" : product.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if allowsLogging, !productObject.isDeleted, productObject.managedObjectContext != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        switch product {
                        case .customUnit(let unit): editor = .customUnit(unit)
                        case .formulation(let formulation): editor = .formulation(formulation)
                        }
                    }
                }
            }
        }
        .sheet(item: $editor, onDismiss: refreshSavedPackages) { editor in
            switch editor {
            case .container:
                NavigationStack { StockContainerEditor(initialProductID: productObject.objectID) }
            case .restock(let container):
                NavigationStack { StockAdjustmentEditor(container: container, action: .restock) }
            case .routine(let schedule, let isNew):
                RoutineScheduleEditor(
                    schedule: schedule, isNew: isNew, store: routines,
                    initialProductID: productObject.objectID, showsProductLink: false
                )
            case .customUnit(let unit):
                NavigationStack { EditCustomUnitsScreen(customUnit: unit) }
            case .formulation(let formulation):
                EditFormulationScreen(formulation: formulation)
            }
        }
        .confirmationDialog("Forget Package Match?", isPresented: Binding(
            get: { packageToForget != nil },
            set: { if !$0 { packageToForget = nil } }
        ), titleVisibility: .visible, presenting: packageToForget) { code in
            Button("Forget", role: .destructive) {
                PharmacyPackageMatches.forget(code)
                refreshSavedPackages()
            }
        } message: { code in
            Text("PZN \(code.digits) will need to be matched again the next time you scan it.")
        }
        .onAppear(perform: refreshSavedPackages)
        .fullScreenCover(isPresented: $logging) {
            AuthenticatorWrapper(authenticator: authenticator) {
                ProductLogScreen(product: product)
            }
        }
        .confirmationDialog("Restock Which Container?", isPresented: $choosingRestockContainer, titleVisibility: .visible) {
            ForEach(activeContainers, id: \.objectID) { container in
                Button(restockLabel(container)) { editor = .restock(container) }
            }
        }
        .task { await routines.refresh() }
    }

    @ViewBuilder
    private var savedPackages: some View {
        if !savedPackageCodes.isEmpty {
            Section("Saved Package Matches") {
                ForEach(savedPackageCodes) { code in
                    Menu {
                        Button(role: .destructive) {
                            packageToForget = code
                        } label: {
                            Label("Forget Match", systemImage: "trash")
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("PZN", value: code.digits)
                            if let context = productObject.managedObjectContext,
                               PharmacyPackageMatches.productID(for: code, in: context) == nil {
                                Text("Review Required").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityHint("Options for this package match")
                }
            }
        }
    }

    private func refreshSavedPackages() {
        savedPackageCodes = PharmacyPackageMatches.codes(for: productObject.objectID)
    }

    @ViewBuilder
    private var definition: some View {
        switch product {
        case .customUnit(let unit):
            Section("Details") {
                LabeledContent("Substance", value: unit.substanceDisplayName)
                LabeledContent("Route", value: unit.administrationRouteUnwrapped.rawValue.localizedCapitalized)
                LabeledContent("Counting Unit", value: unit.unitUnwrapped)
                LabeledContent("Amount per Unit", value: unit.doseOfOneUnitDescription)
                if unit.isArchived { Label("Archived", systemImage: "archivebox") }
                if !unit.noteUnwrapped.isEmpty { Text(unit.noteUnwrapped) }
            }
        case .formulation(let formulation):
            let values = FormulationCodable(formulation)
            Section("Per Serving") {
                ForEach(values.components) { component in
                    LabeledContent {
                        Text(component.doseDescription()).monospacedDigit()
                    } label: {
                        Text(PersistenceController.shared.displayName(for: component.substanceName))
                        Text(component.administrationRoute.rawValue.localizedCapitalized)
                    }
                }
                if !values.note.isEmpty { Text(values.note) }
            }
        }
    }

    private var actions: some View {
        Section {
            if allowsLogging, product.isAvailableForLogging {
                Button {
                    logging = true
                } label: {
                    Label("Log Ingestion", systemImage: "plus.circle")
                }
            }
            JournalPresetShareLink(product: product)
        }
    }

    private var activeContainers: [StockContainer] {
        containers.filter { !$0.isArchived }
    }

    @ViewBuilder
    private var stock: some View {
        Section("Stock") {
            if activeContainers.isEmpty {
                Text("No active containers").foregroundStyle(.secondary)
            }
            containerRows(activeContainers)
            if !activeContainers.isEmpty {
                Button {
                    if activeContainers.count == 1, let container = activeContainers.first {
                        editor = .restock(container)
                    } else {
                        choosingRestockContainer = true
                    }
                } label: {
                    Label("Restock", systemImage: "plus.circle")
                }
            }
            if product.isAvailableForLogging {
                Button {
                    editor = .container
                } label: {
                    Label("Add Container", systemImage: "archivebox")
                }
            }
        }
        let archived = containers.filter(\.isArchived)
        if !archived.isEmpty {
            Section("Archived Containers") {
                containerRows(archived)
            }
        }
    }

    private func containerRows(_ containers: [StockContainer]) -> some View {
        ForEach(containers, id: \.objectID) { container in
            NavigationLink {
                StockContainerDetail(container: container, showsProductLink: false)
            } label: {
                InventorySupplyRow(container: container, showLocation: true)
            }
        }
    }

    private var schedule: some View {
        Section("Routines") {
            let schedules = routineRecords.compactMap(\.schedule).sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            if schedules.isEmpty {
                Text("No routines").foregroundStyle(.secondary)
            }
            ForEach(schedules) { schedule in
                Button {
                    editor = .routine(schedule, isNew: false)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(schedule.name).foregroundStyle(.primary)
                        Text(schedule.summary(unit: product.routineUnit))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .disabled(routines.isUpdating)
            }
            if product.isAvailableForLogging {
                Button {
                    let routine = RoutineSchedule.draft(named: product.name, calendar: RoutineSchedules.calendar)
                    editor = .routine(routine, isNew: true)
                } label: {
                    Label("Add Routine", systemImage: "calendar.badge.plus")
                }
                .disabled(routines.isUpdating || routines.loadError != nil)
            }
        }
    }


    private func restockLabel(_ container: StockContainer) -> String {
        if let location = container.storageLocation {
            return "\(container.displayName) · \(location) · \(container.quantityLabel(container.remaining))"
        }
        return "\(container.displayName) · \(container.quantityLabel(container.remaining))"
    }
}

private struct ProductLogScreen: View {
    let product: JournalPresetProduct

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var locationManager: LocationManager
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch product {
                case .customUnit(let unit):
                    customUnitDose(unit)
                case .formulation(let formulation):
                    FormulationDoseScreen(formulation: formulation, dismiss: close, showsProductLink: false)
                }
            }
            .navigationDestination(for: CustomUnit.self, destination: customUnitDose)
            .navigationDestination(for: FinishIngestionScreenArguments.self) { arguments in
                FinishIngestionScreen(arguments: arguments, dismiss: close)
            }
            .navigationDestination(for: FinishFormulationArguments.self) { arguments in
                FinishIngestionScreen(ingestions: arguments.ingestions, dismiss: close)
            }
        }
        .task { locationManager.maybeRequestLocation() }
    }

    private func customUnitDose(_ unit: CustomUnit) -> some View {
        CustomUnitsChooseDoseScreen(
            customUnit: unit, dismiss: close, navigateToCustomUnitChooseDose: { path.append($0) },
            showsProductLink: false
        )
    }

    private func close() { dismiss() }
}
