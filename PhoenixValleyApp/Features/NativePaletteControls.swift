import SwiftUI
import UIKit

/// Standard UIKit controls keep finger, Pencil and keyboard activation on the
/// same UIControl path, independent of the map's drawing gesture recognizers.
struct PaletteActionButton: UIViewRepresentable {
    let title: String
    let symbol: String
    var selected = false
    let identifier: String
    var iconOnly = false
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        let coordinator = context.coordinator
        button.addAction(UIAction { [weak coordinator] _ in coordinator?.action() }, for: .primaryActionTriggered)
        button.isPointerInteractionEnabled = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        var config = UIButton.Configuration.plain()
        config.title = iconOnly ? nil : title
        config.image = UIImage(systemName: symbol)
        config.imagePlacement = .top
        config.imagePadding = 4
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attributes = incoming; attributes.font = UIFont.systemFont(ofSize: 11, weight: .medium); return attributes
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        config.baseForegroundColor = selected ? .tintColor : .label
        config.background.backgroundColor = selected ? .tintColor.withAlphaComponent(0.13) : .clear
        config.background.cornerRadius = 12
        button.configuration = config
        button.isEnabled = context.environment.isEnabled
        button.isSelected = selected
        button.accessibilityLabel = title
        button.accessibilityIdentifier = identifier
    }
    @MainActor final class Coordinator {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
    }
}

struct PaletteSegments<Value: Hashable>: UIViewRepresentable {
    let titles: [String]
    let values: [Value]
    @Binding var selection: Value
    let label: String
    let identifier: String

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection, values: values) }
    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: titles)
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }
    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.values = values
        control.selectedSegmentIndex = values.firstIndex(of: selection) ?? UISegmentedControl.noSegment
        control.isEnabled = context.environment.isEnabled
        control.accessibilityLabel = label
        control.accessibilityIdentifier = identifier
    }
    @MainActor final class Coordinator: NSObject {
        var selection: Binding<Value>
        var values: [Value]
        init(selection: Binding<Value>, values: [Value]) { self.selection = selection; self.values = values }
        @objc func changed(_ control: UISegmentedControl) {
            guard values.indices.contains(control.selectedSegmentIndex) else { return }
            selection.wrappedValue = values[control.selectedSegmentIndex]
        }
    }
}

struct PaletteSlider: UIViewRepresentable {
    @Binding var value: Double
    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }
    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = 0; slider.maximumValue = 1
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        slider.accessibilityLabel = "笔迹修正强度"
        return slider
    }
    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.value = $value
        slider.value = Float(value)
        slider.isEnabled = context.environment.isEnabled
    }
    @MainActor final class Coordinator: NSObject {
        var value: Binding<Double>
        init(value: Binding<Double>) { self.value = value }
        @objc func changed(_ slider: UISlider) { value.wrappedValue = Double(slider.value) }
    }
}
