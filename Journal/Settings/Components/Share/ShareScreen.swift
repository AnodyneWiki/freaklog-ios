import CoreImage.CIFilterBuiltins
import SwiftUI

struct ShareScreen: View {
    var body: some View {
        List {
            Section("iOS and Android") {
                let link = "https://psychonautwiki.org/wiki/PsychonautWiki_Journal"
                QRCodeView(url: link)
                ShareLink("Share link", item: URL(string: link)!)
                Link(destination: URL(string: link)!) {
                    Label("Open link", systemImage: "safari")
                }
            }
            Section("iOS App") {
                HStack {
                    Text("After download triple tap the closed eye in settings to unlock all substances.")
                    Spacer()
                    Image("Eye Closed")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                }
                let appStoreLink = "https://apps.apple.com/ch/app/psychonautwiki-journal/id1582059415"
                QRCodeView(url: appStoreLink)
                ShareLink("Share app store link", item: URL(string: appStoreLink)!)
                Link(destination: URL(string: appStoreLink)!) {
                    Label("Open app store link", systemImage: "safari")
                }
            }
            Section("Android App") {
                let playStoreLink = "https://play.google.com/store/apps/details?id=com.isaakhanimann.journal"
                QRCodeView(url: playStoreLink)
                ShareLink("Share play store link", item: URL(string: playStoreLink)!)
                Link(destination: URL(string: playStoreLink)!) {
                    Label("Open play store link", systemImage: "safari")
                }
            }
        }
        .navigationTitle("Share App")
    }
}

#Preview {
    NavigationStack {
        ShareScreen()
    }
}
