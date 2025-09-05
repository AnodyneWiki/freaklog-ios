import SwiftUI

struct RelativeTimeText: View {

    let date: Date

    var body: some View {
        TimelineView(.everyMinute) { _ in
            if date > .now {
                Text("in ") + Text(date, style: .relative)
            } else {
                Text(date, style: .relative) + Text(" ago")
            }
        }
    }
}
