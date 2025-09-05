import SwiftUI

struct DotRows: View {
    let numDots: Int

    var body: some View {
        VStack(spacing: 0) {
            if numDots == 0 {
                HStack(spacing: 0) {
                    ForEach(1 ... 4, id: \.self) { _ in
                        Dot(isFull: false)
                    }
                }
            } else if numDots > 20 {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(numDots)x")
                    Dot(isFull: true)
                }
            } else {
                let numFullRows = numDots / 4
                let dotsInLastRow = numDots % 4
                if numFullRows > 0 {
                    ForEach(1 ... numFullRows, id: \.self) { _ in
                        HStack(spacing: 0) {
                            ForEach(1 ... 4, id: \.self) { _ in
                                Dot(isFull: true)
                            }
                        }
                    }
                }
                if dotsInLastRow > 0 {
                    HStack(spacing: 0) {
                        ForEach(1 ... dotsInLastRow, id: \.self) { _ in
                            Dot(isFull: true)
                        }
                        let numEmpty = 4 - dotsInLastRow
                        ForEach(1 ... numEmpty, id: \.self) { _ in
                            Dot(isFull: false)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    DotRows(numDots: 3)
}
