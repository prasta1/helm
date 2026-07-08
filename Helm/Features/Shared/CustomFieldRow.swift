import SwiftUI

/// Renders the appropriate editor control for a custom field based on its type.
///
/// The backing `CustomFieldValue` is materialized lazily via `ensureValue()` —
/// only when the user actually edits the field — so we never insert into the
/// model context during view `body` evaluation.
struct CustomFieldRow: View {
    let field: CustomFieldDefinition
    /// The existing value for this field, if one has been set.
    let value: CustomFieldValue?
    /// Creates (and inserts) the value on first edit, returning the stored one.
    let ensureValue: () -> CustomFieldValue

    var body: some View {
        switch field.type {
        case .text, .url:
            LabeledContent(field.name) {
                TextField(field.name, text: textBinding)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .textInputAutocapitalization(field.type == .url ? .never : .sentences)
                    #endif
            }
        case .multilineText:
            VStack(alignment: .leading) {
                Text(field.name).font(.caption).foregroundStyle(.secondary)
                TextField(field.name, text: textBinding, axis: .vertical)
                    .lineLimit(2...6)
            }
        case .number, .currency:
            LabeledContent(field.name) {
                TextField(field.name, value: numberBinding, format: numberFormat)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
        case .boolean:
            Toggle(field.name, isOn: boolBinding)
        case .date:
            DatePicker(field.name, selection: dateBinding, displayedComponents: .date)
        case .singleSelect:
            Picker(field.name, selection: textBinding) {
                Text("—").tag("")
                ForEach(field.options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        }
    }

    // MARK: Bindings (lazy-materializing)

    private var textBinding: Binding<String> {
        Binding(get: { value?.value ?? "" }, set: { ensureValue().value = $0 })
    }
    private var boolBinding: Binding<Bool> {
        Binding(get: { value?.boolValue ?? false }, set: { ensureValue().boolValue = $0 })
    }
    private var dateBinding: Binding<Date> {
        Binding(get: { value?.dateValue ?? Date() }, set: { ensureValue().dateValue = $0 })
    }
    private var numberBinding: Binding<Double> {
        Binding(get: { value?.doubleValue ?? 0 }, set: { ensureValue().doubleValue = $0 })
    }

    private var numberFormat: FloatingPointFormatStyle<Double> {
        field.type == .currency ? .number.precision(.fractionLength(2)) : .number
    }
}
