import UIKit

/// Extracts metadata from a UIKit view that backs a SwiftUI element.
///
/// SwiftUI renders through UIKit hosting views. This inspector walks the
/// UIView hierarchy to infer the original SwiftUI type, accessibility info,
/// frame, and a rough hierarchy path.
enum ViewInspector {

    // MARK: - Public

    /// Build a `ViewMetadata` snapshot from a hit-tested UIView.
    static func extractMetadata(from view: UIView) -> ViewMetadata {
        let rawClassName = String(describing: type(of: view))
        let viewType = inferSwiftUIType(from: view, className: rawClassName)
        let windowFrame = view.convert(view.bounds, to: nil)
        let parentFrame = view.frame
        let path = buildViewPath(from: view)

        return ViewMetadata(
            viewType: viewType,
            accessibilityIdentifier: findAccessibilityIdentifier(from: view),
            accessibilityLabel: findAccessibilityLabel(from: view),
            accessibilityTraits: view.accessibilityTraits,
            frame: parentFrame,
            windowFrame: windowFrame,
            viewPath: path,
            rawClassName: rawClassName
        )
    }

    // MARK: - Type Inference

    /// Map UIKit backing view class names and traits to SwiftUI type names.
    private static func inferSwiftUIType(from view: UIView, className: String) -> String {
        // Direct UIKit type matches
        if view is UIButton { return "Button" }
        if view is UILabel { return "Text" }
        if view is UIImageView { return "Image" }
        if view is UITextField { return "TextField" }
        if view is UITextView { return "TextEditor" }
        if view is UISwitch { return "Toggle" }
        if view is UISlider { return "Slider" }
        if view is UIScrollView { return "ScrollView" }
        if view is UITableView { return "List" }
        if view is UICollectionView { return "List/Grid" }
        if view is UINavigationBar { return "NavigationBar" }
        if view is UITabBar { return "TabBar" }
        if view is UIProgressView { return "ProgressView" }
        if view is UIActivityIndicatorView { return "ProgressView" }
        if view is UISegmentedControl { return "Picker (segmented)" }
        if view is UIDatePicker { return "DatePicker" }
        if view is UIStepper { return "Stepper" }

        // SwiftUI internal class name heuristics
        let lowered = className.lowercased()

        if lowered.contains("button") { return "Button" }
        if lowered.contains("textfield") { return "TextField" }
        if lowered.contains("textdisplay") || lowered.contains("statictext") { return "Text" }
        if lowered.contains("cgdrawingview") { return "Shape/Canvas" }
        if lowered.contains("imageview") { return "Image" }
        if lowered.contains("switch") || lowered.contains("toggle") { return "Toggle" }
        if lowered.contains("slider") { return "Slider" }
        if lowered.contains("scrollview") { return "ScrollView" }
        if lowered.contains("listview") || lowered.contains("tableview") { return "List" }
        if lowered.contains("collectionview") || lowered.contains("gridview") { return "Grid" }
        if lowered.contains("navigationbar") { return "NavigationBar" }
        if lowered.contains("tabbar") { return "TabBar" }
        if lowered.contains("picker") { return "Picker" }
        if lowered.contains("mapview") { return "Map" }

        // Accessibility-trait-based fallback
        let traits = view.accessibilityTraits
        if traits.contains(.button) { return "Button" }
        if traits.contains(.image) { return "Image" }
        if traits.contains(.link) { return "Link" }
        if traits.contains(.header) { return "Header (Text)" }
        if traits.contains(.staticText) { return "Text" }
        if traits.contains(.searchField) { return "SearchField" }
        if traits.contains(.adjustable) { return "Slider/Stepper" }
        if traits.contains(.tabBar) { return "TabView" }

        // Clean up the raw class name as a last resort
        return cleanClassName(className)
    }

    /// Strip SwiftUI/UIKit internal prefixes and generic parameters.
    private static func cleanClassName(_ name: String) -> String {
        var cleaned = name

        // Strip common prefixes
        for prefix in ["SwiftUI.", "_UI", "UI", "_", "Hosting"] {
            if cleaned.hasPrefix(prefix) && cleaned.count > prefix.count {
                cleaned = String(cleaned.dropFirst(prefix.count))
            }
        }

        // Truncate generic type parameters
        if let bracket = cleaned.firstIndex(of: "<") {
            cleaned = String(cleaned[..<bracket])
        }

        // Remove "Representable", "Platform", "Container" noise
        for noise in ["Representable", "Platform", "Container", "Wrapper"] {
            cleaned = cleaned.replacingOccurrences(of: noise, with: "")
        }

        return cleaned.isEmpty ? "View" : cleaned
    }

    // MARK: - Accessibility Lookup

    /// Walk up the view hierarchy to find the nearest accessibility identifier.
    private static func findAccessibilityIdentifier(from view: UIView) -> String? {
        var current: UIView? = view
        var depth = 0
        while let v = current, depth < 5 {
            if let id = v.accessibilityIdentifier, !id.isEmpty {
                return id
            }
            current = v.superview
            depth += 1
        }
        return nil
    }

    /// Walk up the view hierarchy to find the nearest accessibility label.
    private static func findAccessibilityLabel(from view: UIView) -> String? {
        var current: UIView? = view
        var depth = 0
        while let v = current, depth < 5 {
            if let label = v.accessibilityLabel, !label.isEmpty {
                return label
            }
            current = v.superview
            depth += 1
        }
        return nil
    }

    // MARK: - View Path

    /// Walk up the superview chain and build a hierarchy path string.
    private static func buildViewPath(from view: UIView) -> String {
        var components: [String] = []
        var current: UIView? = view
        var seen = Set<String>() // deduplicate consecutive identical types

        while let v = current {
            let raw = String(describing: type(of: v))
            let name = inferSwiftUIType(from: v, className: raw)

            // Stop at the hosting view root
            if raw.contains("UIHostingView") || raw.contains("_UIHostingView") {
                components.append("HostingView")
                break
            }

            // Skip generic containers and duplicates for a cleaner path
            let skip = ["View", "ContentView", "ViewHost", "TransitionView",
                        "PlatformViewHost", "LayoutContainer"]
            if !skip.contains(name) && !seen.contains(name) {
                components.append(name)
                seen.insert(name)
            }

            current = v.superview

            // Safety cap
            if components.count >= 10 { break }
        }

        if components.isEmpty {
            return "View"
        }

        return components.reversed().joined(separator: " > ")
    }
}
