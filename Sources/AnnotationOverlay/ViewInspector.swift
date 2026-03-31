/// Extracts metadata from a platform-native view that backs a SwiftUI element.
///
/// SwiftUI renders through platform hosting views (UIKit on iOS, AppKit on macOS).
/// This inspector walks the view hierarchy to infer the original SwiftUI type,
/// accessibility info, frame, and a rough hierarchy path.
enum ViewInspector {

    /// Build a `ViewMetadata` snapshot from a hit-tested platform view.
    static func extractMetadata(from view: PlatformView) -> ViewMetadata {
        let rawClassName = String(describing: type(of: view))
        let viewType = inferSwiftUIType(from: view, className: rawClassName)
        let windowFrame = windowFrame(for: view)
        let parentFrame = view.frame
        let path = buildViewPath(from: view)

        return ViewMetadata(
            viewType: viewType,
            accessibilityIdentifier: findAccessibilityIdentifier(from: view),
            accessibilityLabel: findAccessibilityLabel(from: view),
            accessibilityTraits: extractTraits(from: view),
            frame: parentFrame,
            windowFrame: windowFrame,
            viewPath: path,
            rawClassName: rawClassName
        )
    }
}

// MARK: - Shared Helpers

extension ViewInspector {

    /// Strip SwiftUI/platform internal prefixes and generic parameters from a class name.
    fileprivate static func cleanClassName(_ name: String) -> String {
        var cleaned = name

        for prefix in ["SwiftUI.", "_NS", "NS", "_UI", "UI", "_", "Hosting"] {
            if cleaned.hasPrefix(prefix) && cleaned.count > prefix.count {
                cleaned = String(cleaned.dropFirst(prefix.count))
            }
        }

        if let bracket = cleaned.firstIndex(of: "<") {
            cleaned = String(cleaned[..<bracket])
        }

        for noise in ["Representable", "Platform", "Container", "Wrapper"] {
            cleaned = cleaned.replacingOccurrences(of: noise, with: "")
        }

        return cleaned.isEmpty ? "View" : cleaned
    }

    /// Class-name-based heuristics shared across platforms.
    fileprivate static func inferFromClassName(_ className: String) -> String? {
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
        if lowered.contains("navigationbar") || lowered.contains("toolbar") { return "Toolbar" }
        if lowered.contains("tabbar") || lowered.contains("tabview") { return "TabView" }
        if lowered.contains("picker") { return "Picker" }
        if lowered.contains("mapview") { return "Map" }

        return nil
    }

    /// True if the raw class name indicates a hosting view root.
    fileprivate static func isHostingView(_ className: String) -> Bool {
        className.contains("HostingView") || className.contains("_UIHostingView")
            || className.contains("_NSHostingView")
    }

    /// Names to skip when building the view path.
    fileprivate static let pathSkipNames: Set<String> = [
        "View", "ContentView", "ViewHost", "TransitionView",
        "PlatformViewHost", "LayoutContainer",
    ]

    /// Check if a view belongs to our annotation overlay chrome.
    fileprivate static func isOverlayView(_ view: PlatformView) -> Bool {
        #if canImport(UIKit)
        if let id = view.accessibilityIdentifier, id.hasPrefix("_annotationOverlay") {
            return true
        }
        #elseif canImport(AppKit)
        let id = view.accessibilityIdentifier()
        if id.hasPrefix("_annotationOverlay") {
            return true
        }
        #endif
        return false
    }
}

// MARK: - iOS (UIKit)

#if canImport(UIKit)
import UIKit

extension ViewInspector {

    /// Walk the entire subview tree to find the deepest, most specific view
    /// containing the given window-coordinate point.
    ///
    /// Unlike `UIView.hitTest`, this ignores `isUserInteractionEnabled` and
    /// gesture recognizers — it purely checks geometric containment so we can
    /// find non-interactive SwiftUI elements (Text, Image, etc.) that don't
    /// normally participate in hit-testing.
    static func deepestView(at windowPoint: CGPoint, in root: UIView) -> UIView {
        // Walk subviews front-to-back (reversed because UIView.subviews is back-to-front)
        for subview in root.subviews.reversed() {
            guard !subview.isHidden, subview.alpha > 0.01 else { continue }

            // Skip our own overlay views
            if isOverlayView(subview) { continue }

            let subLocal = subview.convert(windowPoint, from: nil)
            guard subview.bounds.contains(subLocal) else { continue }

            return deepestView(at: windowPoint, in: subview)
        }

        return root
    }

    fileprivate static func windowFrame(for view: UIView) -> CGRect {
        view.convert(view.bounds, to: nil)
    }

    fileprivate static func inferSwiftUIType(from view: UIView, className: String) -> String {
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

        // Class name heuristics
        if let match = inferFromClassName(className) { return match }

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

        return cleanClassName(className)
    }

    fileprivate static func extractTraits(from view: UIView) -> [String] {
        var parts: [String] = []
        let t = view.accessibilityTraits
        if t.contains(.button) { parts.append("button") }
        if t.contains(.link) { parts.append("link") }
        if t.contains(.image) { parts.append("image") }
        if t.contains(.header) { parts.append("header") }
        if t.contains(.staticText) { parts.append("staticText") }
        if t.contains(.searchField) { parts.append("searchField") }
        if t.contains(.adjustable) { parts.append("adjustable") }
        if t.contains(.selected) { parts.append("selected") }
        if t.contains(.notEnabled) { parts.append("notEnabled") }
        if t.contains(.updatesFrequently) { parts.append("updatesFrequently") }
        if t.contains(.summaryElement) { parts.append("summaryElement") }
        if t.contains(.tabBar) { parts.append("tabBar") }
        return parts
    }

    fileprivate static func findAccessibilityIdentifier(from view: UIView) -> String? {
        var current: UIView? = view
        for _ in 0..<5 {
            guard let v = current else { break }
            if let id = v.accessibilityIdentifier, !id.isEmpty { return id }
            current = v.superview
        }
        return nil
    }

    fileprivate static func findAccessibilityLabel(from view: UIView) -> String? {
        var current: UIView? = view
        for _ in 0..<5 {
            guard let v = current else { break }
            if let label = v.accessibilityLabel, !label.isEmpty { return label }
            current = v.superview
        }
        return nil
    }

    fileprivate static func buildViewPath(from view: UIView) -> String {
        var components: [String] = []
        var current: UIView? = view
        var seen = Set<String>()

        while let v = current {
            let raw = String(describing: type(of: v))

            if isHostingView(raw) {
                components.append("HostingView")
                break
            }

            let name = inferSwiftUIType(from: v, className: raw)
            if !pathSkipNames.contains(name) && !seen.contains(name) {
                components.append(name)
                seen.insert(name)
            }

            current = v.superview
            if components.count >= 10 { break }
        }

        return components.isEmpty ? "View" : components.reversed().joined(separator: " > ")
    }
}

// MARK: - macOS (AppKit)

#elseif canImport(AppKit)
import AppKit

extension ViewInspector {

    /// Walk the entire subview tree to find the deepest, most specific view
    /// containing the given window-coordinate point.
    ///
    /// This bypasses `NSView.hitTest` entirely — which avoids coordinate-space
    /// confusion and finds non-interactive SwiftUI elements that `hitTest` skips.
    static func deepestView(at windowPoint: CGPoint, in root: NSView) -> NSView {
        // NSView.subviews is back-to-front; reversed gives us front-to-back
        for subview in root.subviews.reversed() {
            guard !subview.isHidden, subview.alphaValue > 0.01 else { continue }

            // Skip our own overlay views
            if isOverlayView(subview) { continue }

            let subLocal = subview.convert(windowPoint, from: nil)
            guard subview.bounds.contains(subLocal) else { continue }

            return deepestView(at: windowPoint, in: subview)
        }

        return root
    }

    fileprivate static func windowFrame(for view: NSView) -> CGRect {
        guard let window = view.window else { return view.frame }
        let frameInWindow = view.convert(view.bounds, to: nil)
        // Convert from AppKit's bottom-left origin to top-left for consistency
        let windowHeight = window.contentView?.bounds.height ?? window.frame.height
        return CGRect(
            x: frameInWindow.origin.x,
            y: windowHeight - frameInWindow.origin.y - frameInWindow.height,
            width: frameInWindow.width,
            height: frameInWindow.height
        )
    }

    fileprivate static func inferSwiftUIType(from view: NSView, className: String) -> String {
        // Direct AppKit type matches
        if view is NSButton { return "Button" }
        if view is NSImageView { return "Image" }
        if view is NSTextField {
            let tf = view as! NSTextField
            return tf.isEditable ? "TextField" : "Text"
        }
        if view is NSTextView { return "TextEditor" }
        if view is NSSwitch { return "Toggle" }
        if view is NSSlider { return "Slider" }
        if view is NSScrollView { return "ScrollView" }
        if view is NSTableView { return "List" }
        if view is NSCollectionView { return "Grid" }
        if view is NSProgressIndicator { return "ProgressView" }
        if view is NSSegmentedControl { return "Picker (segmented)" }
        if view is NSDatePicker { return "DatePicker" }
        if view is NSStepper { return "Stepper" }
        if view is NSTabView { return "TabView" }
        if view is NSSplitView { return "HSplitView/VSplitView" }
        if view is NSStackView { return "HStack/VStack" }

        // Class name heuristics
        if let match = inferFromClassName(className) { return match }

        // Accessibility-role-based fallback
        let role = view.accessibilityRole()
        if role == .button { return "Button" }
        if role == .image { return "Image" }
        if role == .link { return "Link" }
        if role == .staticText { return "Text" }
        if role == .textField { return "TextField" }
        if role == .slider { return "Slider" }
        if role == .checkBox { return "Toggle" }
        if role == .list { return "List" }
        if role == .table { return "List" }
        if role == .tabGroup { return "TabView" }
        if role == .toolbar { return "Toolbar" }
        if role == .scrollArea { return "ScrollView" }
        if role == .progressIndicator { return "ProgressView" }

        return cleanClassName(className)
    }

    fileprivate static func extractTraits(from view: NSView) -> [String] {
        var parts: [String] = []
        let role = view.accessibilityRole()

        if role == .button { parts.append("button") }
        if role == .link { parts.append("link") }
        if role == .image { parts.append("image") }
        if role == .staticText { parts.append("staticText") }
        if role == .textField { parts.append("textField") }
        if role == .checkBox { parts.append("toggle") }
        if role == .slider { parts.append("adjustable") }
        if role == .list || role == .table { parts.append("list") }
        if role == .tabGroup { parts.append("tabGroup") }

        if !view.isAccessibilityEnabled() { parts.append("notEnabled") }

        return parts
    }

    fileprivate static func findAccessibilityIdentifier(from view: NSView) -> String? {
        var current: NSView? = view
        for _ in 0..<5 {
            guard let v = current else { break }
            let id = v.accessibilityIdentifier()
            if !id.isEmpty { return id }
            current = v.superview
        }
        return nil
    }

    fileprivate static func findAccessibilityLabel(from view: NSView) -> String? {
        var current: NSView? = view
        for _ in 0..<5 {
            guard let v = current else { break }
            if let label = v.accessibilityLabel(), !label.isEmpty { return label }
            current = v.superview
        }
        return nil
    }

    fileprivate static func buildViewPath(from view: NSView) -> String {
        var components: [String] = []
        var current: NSView? = view
        var seen = Set<String>()

        while let v = current {
            let raw = String(describing: type(of: v))

            if isHostingView(raw) {
                components.append("HostingView")
                break
            }

            let name = inferSwiftUIType(from: v, className: raw)
            if !pathSkipNames.contains(name) && !seen.contains(name) {
                components.append(name)
                seen.insert(name)
            }

            current = v.superview
            if components.count >= 10 { break }
        }

        return components.isEmpty ? "View" : components.reversed().joined(separator: " > ")
    }
}

#endif
