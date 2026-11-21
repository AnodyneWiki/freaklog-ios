import Charts
import SwiftUI

struct SubstanceDetailsScreen: View {
    let substanceData: SubstanceData
    @State private var timeRange: TimeRange = .last12Months

    var data: [SubstanceCount] {
        substanceData.counts(in: timeRange)
    }

    var body: some View {
        List {
            Section {
                TimeRangePicker(value: $timeRange)
                    .padding(.vertical, 5)
                if let maxCount = data.first?.experienceCount {
                    ForEach(data) { elem in
                        NavigationLink(value: GlobalNavigationDestination.dosageStat(substanceName: elem.substanceName)) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(elem.substanceName)
                                        .font(.headline)
                                    Spacer()
                                    Text(elem.experienceCount.with(pluralizableUnit: PluralizableUnit(singular: "experience", plural: "experiences")))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                let widthRatio = Double(elem.experienceCount) / Double(maxCount)
                                GeometryReader { geometry in
                                    Rectangle()
                                        .fill(substanceData.color(for: elem.substanceName))
                                        .cornerRadius(5, corners: [.topRight, .bottomRight])
                                        .frame(
                                            width: geometry.size.width * widthRatio
                                        )
                                }
                                .frame(height: 20)
                            }
                        }
                    }
                } else {
                    Text("No experiences").font(.headline)
                }
            } footer: {
                Text("Each occurence of the substance in an experience is counted as 1.")
            }
        }
        .navigationTitle("Substances")
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

#Preview {
    NavigationStack {
        SubstanceDetailsScreen(substanceData: .mock2)
    }
}
