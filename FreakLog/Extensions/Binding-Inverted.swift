import SwiftUI

extension Binding where Value == Bool {
  // Lets a toggle read positively ("Dosage dots") while the stored setting stays negated ("is hiding").
  var inverted: Binding<Bool> {
    Binding(get: { !wrappedValue }, set: { wrappedValue = !$0 })
  }
}
