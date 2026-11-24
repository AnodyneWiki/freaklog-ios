import SwiftUI

// Picks a dose with the Digital Crown, starting at the latest one, and logs it now
struct OtherDoseScreen: View {
  init(suggestion: WatchSuggestion) {
    self.suggestion = suggestion
    _amount = State(initialValue: suggestion.typicalDose)
  }

  let suggestion: WatchSuggestion

  var body: some View {
    VStack(spacing: 2) {
      Text(amountText)
        .font(.system(size: 44, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(suggestion.swiftUIColor)
        .contentTransition(.numericText(value: amount))
        .animation(.snappy, value: amount)
        .minimumScaleFactor(0.5)
        .lineLimit(1)
      Text(unitText)
        .font(.headline)
      if let calculated = suggestion.calculatedDescription(of: dose) {
        Text(calculated)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .focusable()
    .focused($isCrownFocused)
    .digitalCrownRotation(
      $amount,
      from: 0,
      through: maxAmount,
      by: step,
      sensitivity: .medium,
      isContinuous: false,
      isHapticFeedbackEnabled: true)
    .accessibilityElement(children: .combine)
    .accessibilityValue(suggestion.description(of: dose))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        change(by: step)
      case .decrement:
        change(by: -step)
      @unknown default:
        break
      }
    }
    .navigationTitle(suggestion.title)
    .toolbar {
      ToolbarItemGroup(placement: .bottomBar) {
        Button {
          change(by: -step)
        } label: {
          Image(systemName: "minus")
        }
        .accessibilityLabel("Decrease")
        .disabled(amount <= 0)
        Button {
          model.log(dose, of: suggestion)
        } label: {
          Text("Log")
            .fontWeight(.semibold)
        }
        .tint(suggestion.swiftUIColor)
        .disabled(amount <= 0)
        Button {
          change(by: step)
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel("Increase")
      }
    }
    .onAppear {
      isCrownFocused = true
    }
  }

  @EnvironmentObject private var model: QuickLogModel
  @State private var amount: Double
  @FocusState private var isCrownFocused: Bool

  private var step: Double {
    suggestion.doseStep
  }

  // Leaves room above the usual doses without making the crown too coarse
  private var maxAmount: Double {
    max(suggestion.typicalDose * 5, step * 100)
  }

  private var dose: WatchDose {
    WatchDose(amount: amount, isEstimate: false, standardDeviation: nil)
  }

  private var amountText: String {
    amount.asRoundedReadableString
  }

  private var unitText: String {
    if suggestion.formulation != nil {
      return "×"
    }
    return suggestion.customUnit?.unitName(for: amount) ?? suggestion.units
  }

  private func change(by delta: Double) {
    // Snaps to the crown's steps, so 0.1 + 0.2 doesn't show as 0.30000000000000004
    let snapped = ((amount + delta) / step).rounded() * step
    amount = min(max(snapped, 0), maxAmount)
  }
}
