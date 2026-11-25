import OSLog
import SwiftUI
import UIKit

@MainActor
struct AppIconSettingsScreen: View {
    @EnvironmentObject private var toastViewModel: ToastViewModel
    @State private var selectedIconName = UIApplication.shared.alternateIconName
    @State private var isChangingIcon = false

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FreakLog", category: "AppIcon")

    var body: some View {
        List {
            ForEach(AppIcon.allCases, id: \.self) { icon in
                let isSelected = selectedIconName == icon.alternateName
                Button {
                    changeIcon(to: icon)
                } label: {
                    HStack(spacing: 12) {
                        Image(icon.preview)
                            .resizable()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .accessibilityHidden(true)
                        Text(icon.title)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .disabled(isChangingIcon)
        .navigationTitle("App Icon")
    }

    private func changeIcon(to icon: AppIcon) {
        guard !isChangingIcon, selectedIconName != icon.alternateName else { return }
        isChangingIcon = true
        Task {
            let application = UIApplication.shared
            defer {
                selectedIconName = application.alternateIconName
                isChangingIcon = false
            }
            do {
                try await application.setAlternateIconName(icon.alternateName)
            } catch {
                Self.logger.error("App icon change returned an error: \(String(describing: error), privacy: .public)")
                // The simulator can apply an icon before its confirmation alert fails.
                guard application.alternateIconName != icon.alternateName else { return }
                #if targetEnvironment(simulator)
                let failure = error as NSError
                if failure.domain == NSPOSIXErrorDomain && (failure.code == Int(EIO) || failure.code == Int(EAGAIN)) {
                    toastViewModel.showErrorToast(message: "Icon changes are unavailable in this simulator")
                    return
                }
                #endif
                toastViewModel.showErrorToast(message: "Couldn’t change the app icon")
            }
        }
    }
}

private enum AppIcon: CaseIterable {
    case psychonautWiki
    case psyLog

    var title: LocalizedStringKey {
        switch self {
        case .psychonautWiki: "PsychonautWiki Journal"
        case .psyLog: "PsyLog"
        }
    }

    var alternateName: String? {
        switch self {
        case .psychonautWiki: nil
        case .psyLog: "AppIconPsyLog"
        }
    }

    var preview: String {
        switch self {
        case .psychonautWiki: "AppIconPWPreview"
        case .psyLog: "AppIconPsyLogPreview"
        }
    }
}
