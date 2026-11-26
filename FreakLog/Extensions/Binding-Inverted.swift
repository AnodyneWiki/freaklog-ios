import SwiftUI

extension Binding where Value == Bool {
  // Lets a toggle read positively ("Dosage dots") while the stored setting stays negated ("is hiding").
  var inverted: Binding<Bool> {
    Binding(get: { !wrappedValue }, set: { wrappedValue = !$0 })
  }
}

extension Binding {
  // Whether the set holds the element; turning it on inserts it, turning it off removes it
  func contains<Element>(_ element: Element) -> Binding<Bool> where Value == Set<Element> {
    Binding<Bool>(
      get: { wrappedValue.contains(element) },
      set: { isContained in
        if isContained {
          wrappedValue.insert(element)
        } else {
          wrappedValue.remove(element)
        }
      }
    )
  }
}
