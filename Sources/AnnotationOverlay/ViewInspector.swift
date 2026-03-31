/// Extracts metadata from platform-native views and accessibility elements
/// that back SwiftUI elements.
///
/// SwiftUI often renders multiple views (Text, Image, etc.) into a single
/// shared drawing layer with no individual platform views. The accessibility
/// tree, however, always has per-element entries. This inspector uses
/// `accessibilityHitTest` as the **primary** detection mechanism, falling
/// back to view-hierarchy walking only when accessibility returns nothing.
enum ViewInspector {

    /// Build a `ViewMetadata` snapshot from a platform view.
    static func extractMetadata(from view: PlatformView) -> ViewMetadata {
        let rawClassName = String(describing: type(of: view))
        let viewType = inferSwiftUIType(from: view, className: rawClassName)
        let wFrame = windowFrame(for: view)
        let parentFrame = view.frame
        let path = buildViewPath(from: view)

        return ViewMetadata(
            viewType: viewType,
            accessibilityIdentifier: findAccessibilityIdentifier(from: view),
            accessibilityLabel: findAccessibilityLabel(from: view),
            accessibilityTraits: extractTraits(from: view),
            frame: parentFrame,
            windowFrame: wFrame,
            viewPath: path,
            rawClassName: rawClassName
        )
    }
}

// MARK: - Shared Helpers

extension ViewInspector {

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

    fileprivate static func isHostingView(_ className: String) -> Bool {
        className.contains("HostingView") || className.contains("_UIHostingView")
            || className.contains("_NSHostingView")
    }

    fileprivate static let pathSkipNames: Set<String> = [
        "View", "ContentView", "ViewHost", "TransitionView",
        "PlatformViewHost", "LayoutContainer",
    ]

    fileprivate static func isOverlayView(_ view: PlatformView) -> Bool {
        #if canImport(UIKit)
        if let id = view.accessibilityIdentifier, id.hasPrefix("_annotationOverlay") { return true }
        #elseif canImport(AppKit)
        if view.accessibilityIdentifier().hasPrefix("_annotationOverlay") { return true }
        #endif
        return false
    }
}

// MARK: - iOS (UIKit)

#if canImport(UIKit)
import UIKit

extension ViewInspector {

    // MARK: Primary entry point

    /// Find the most specific element at a window-coordinate point.
    /// Uses the accessibility tree first, then falls back to the view hierarchy.
    static func findMetadata(at windowPoint: CGPoint, in window: UIWindow) -> ViewMetadata? {
        // Accessibility hit-test: check the deepest view's accessibility elements
        // On iOS, we find the deepest view first, then refine with accessibility
        guard let rootView = window.rootViewController?.view else { return nil }

        let deepest = deepestView(at: windowPoint, in: rootView)
        if isOverlayView(deepest) { return nil }

        // Search accessibility elements of the deepest view (and ancestors)
        // for a more specific match at this point
        let screenPoint = windowPoint // On iOS, window coords ≈ screen coords
        if let accMetadata = findAccessibilityMetadata(at: screenPoint, in: deepest) {
            return accMetadata
        }

        // Fall back to the view-based extraction
        return extractMetadata(from: deepest)
    }

    // MARK: Accessibility element search (iOS)

    /// Walk the accessibility elements of a view (and a few ancestors) looking
    /// for the most specific element whose frame contains the given screen point.
    private static func findAccessibilityMetadata(at screenPoint: CGPoint, in view: UIView) -> ViewMetadata? {
        var current: UIView? = view
        // Check the view and up to 3 ancestors for accessibility elements
        for _ in 0..<4 {
            guard let v = current else { break }

            if let elements = v.accessibilityElements {
                // Find the smallest element containing the point
                var bestMatch: NSObject?
                var bestArea: CGFloat = .greatestFiniteMagnitude

                for element in elements {
                    guard let obj = element as? NSObject else { continue }
                    let frame = obj.accessibilityFrame
                    guard frame.contains(screenPoint), !frame.isEmpty else { continue }
                    let area = frame.width * frame.height
                    if area < bestArea {
                        bestArea = area
                        bestMatch = obj
                    }
                }

                if let match = bestMatch {
                    return extractFromAccessibilityObject(match, screenFrame: match.accessibilityFrame)
                }
            }

            current = v.superview
        }

        return nil
    }

    /// Build ViewMetadata from an iOS accessibility object (UIAccessibilityElement or similar).
    private static func extractFromAccessibilityObject(_ obj: NSObject, screenFrame: CGRect) -> ViewMetadata {
        let traits = obj.accessibilityTraits
        let viewType = traitsToTypeName(traits)

        var traitNames: [String] = []
        if traits.contains(.button) { traitNames.append("button") }
        if traits.contains(.link) { traitNames.append("link") }
        if traits.contains(.image) { traitNames.append("image") }
        if traits.contains(.header) { traitNames.append("header") }
        if traits.contains(.staticText) { traitNames.append("staticText") }
        if traits.contains(.searchField) { traitNames.append("searchField") }
        if traits.contains(.adjustable) { traitNames.append("adjustable") }
        if traits.contains(.selected) { traitNames.append("selected") }

        let rawClassName = String(describing: type(of: obj))

        return ViewMetadata(
            viewType: viewType,
            accessibilityIdentifier: (obj as? UIAccessibilityIdentification)?.accessibilityIdentifier,
            accessibilityLabel: obj.accessibilityLabel,
            accessibilityTraits: traitNames,
            frame: screenFrame,
            windowFrame: screenFrame,
            viewPath: buildAccessibilityPath(from: obj),
            rawClassName: rawClassName
        )
    }

    private static func traitsToTypeName(_ traits: UIAccessibilityTraits) -> String {
        if traits.contains(.button) { return "Button" }
        if traits.contains(.image) { return "Image" }
        if traits.contains(.link) { return "Link" }
        if traits.contains(.header) { return "Header" }
        if traits.contains(.staticText) { return "Text" }
        if traits.contains(.searchField) { return "SearchField" }
        if traits.contains(.adjustable) { return "Slider/Stepper" }
        return "View"
    }

    private static func buildAccessibilityPath(from obj: NSObject) -> String {
        // iOS accessibility elements don't have a parent chain we can walk easily,
        // so return a basic path from the object's type.
        let viewType: String
        if let traits = (obj as AnyObject).accessibilityTraits {
            viewType = traitsToTypeName(traits)
        } else {
            viewType = "View"
        }
        return "HostingView > \(viewType)"
    }

    // MARK: Deep subview walk

    static func deepestView(at windowPoint: CGPoint, in root: UIView) -> UIView {
        for subview in root.subviews.reversed() {
            guard !subview.isHidden, subview.alpha > 0.01 else { continue }
            if isOverlayView(subview) { continue }
            let subLocal = subview.convert(windowPoint, from: nil)
            guard subview.bounds.contains(subLocal) else { continue }
            return deepestView(at: windowPoint, in: subview)
        }
        return root
    }

    // MARK: View-based helpers

    fileprivate static func windowFrame(for view: UIView) -> CGRect {
        view.convert(view.bounds, to: nil)
    }

    fileprivate static func inferSwiftUIType(from view: UIView, className: String) -> String {
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

        if let match = inferFromClassName(className) { return match }

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

    // MARK: Primary entry point

    /// Find the most specific element at a window-coordinate point.
    /// Uses `accessibilityHitTest` first (finds individual SwiftUI elements even
    /// when they share a drawing layer), then falls back to the view hierarchy.
    static func findMetadata(at windowPoint: CGPoint, in window: NSWindow) -> ViewMetadata? {
        guard let contentView = window.contentView else { return nil }

        // Convert window point → screen point for accessibility APIs.
        // AppKit screen coordinates use bottom-left origin.
        let screenRect = window.convertToScreen(NSRect(origin: windowPoint, size: .zero))
        let screenPoint = screenRect.origin

        // 1. Try accessibility hit-test (primary — finds per-element in SwiftUI)
        if let element = contentView.accessibilityHitTest(screenPoint) {
            // If it returned a more specific element (not the contentView itself)
            let isSameAsRoot: Bool
            if let view = element as? NSView {
                isSameAsRoot = (view === contentView)
            } else {
                isSameAsRoot = false
            }

            if !isSameAsRoot {
                if let metadata = extractFromAccessibilityHit(element, in: window) {
                    // Skip our overlay chrome
                    if let id = metadata.accessibilityIdentifier, id.hasPrefix("_annotationOverlay") {
                        // fall through
                    } else {
                        return metadata
                    }
                }
            }
        }

        // 2. Fall back to deepest subview walk
        let deepest = deepestView(at: windowPoint, in: contentView)
        if isOverlayView(deepest) { return nil }
        return extractMetadata(from: deepest)
    }

    // MARK: Accessibility metadata extraction (macOS)

    /// Extract ViewMetadata from whatever `accessibilityHitTest` returned.
    /// This can be an NSView or a SwiftUI-internal accessibility element.
    private static func extractFromAccessibilityHit(_ element: Any, in window: NSWindow) -> ViewMetadata? {
        // If it's an NSView, use the richer view-based extraction
        if let view = element as? NSView {
            if isOverlayView(view) { return nil }
            return extractMetadata(from: view)
        }

        // For non-view accessibility elements (SwiftUI's internal elements),
        // use NSAccessibilityElementProtocol for frame/parent/identifier,
        // and ObjC runtime for role/label (which are on the NSAccessibility protocol
        // that these internal objects implement but Swift can't statically cast to).
        guard let accessible = element as? NSAccessibilityElementProtocol else { return nil }

        let screenFrame = accessible.accessibilityFrame()
        guard !screenFrame.isEmpty, screenFrame.width > 0, screenFrame.height > 0 else { return nil }

        // Convert screen frame → window frame → top-left origin
        let topLeftFrame = normalizeScreenFrame(screenFrame, in: window)

        let identifier = accessible.accessibilityIdentifier?()
        let rawClassName = String(describing: type(of: element))

        // Use ObjC runtime to get role and label from the accessibility element.
        // These are defined on NSAccessibility protocol which SwiftUI's internal
        // elements implement, but Swift can't cast to the protocol directly.
        var viewType = "View"
        var label: String? = nil
        var traits: [String] = []

        if let obj = element as? NSObject {
            // accessibilityRole() returns NSAccessibility.Role (String rawValue)
            let roleSel = NSSelectorFromString("accessibilityRole")
            if obj.responds(to: roleSel),
               let roleStr = obj.perform(roleSel)?.takeUnretainedValue() as? String {
                let role = NSAccessibility.Role(rawValue: roleStr)
                viewType = roleToTypeName(role)
                traits = roleToTraits(role)
            }

            let labelSel = NSSelectorFromString("accessibilityLabel")
            if obj.responds(to: labelSel),
               let labelStr = obj.perform(labelSel)?.takeUnretainedValue() as? String,
               !labelStr.isEmpty {
                label = labelStr
            }
        }

        // Fall back to class name inference if role didn't resolve
        if viewType == "View", let inferred = inferFromClassName(rawClassName) {
            viewType = inferred
        }

        return ViewMetadata(
            viewType: viewType,
            accessibilityIdentifier: (identifier?.isEmpty ?? true) ? nil : identifier,
            accessibilityLabel: label,
            accessibilityTraits: traits,
            frame: topLeftFrame,
            windowFrame: topLeftFrame,
            viewPath: buildAccessibilityPath(from: element),
            rawClassName: rawClassName
        )
    }

    /// Convert an AppKit screen-coordinate frame to top-left window coordinates.
    private static func normalizeScreenFrame(_ screenFrame: NSRect, in window: NSWindow) -> CGRect {
        let windowRect = window.convertFromScreen(screenFrame)
        let contentHeight = window.contentView?.bounds.height ?? window.frame.height
        return CGRect(
            x: windowRect.origin.x,
            y: contentHeight - windowRect.origin.y - windowRect.height,
            width: windowRect.width,
            height: windowRect.height
        )
    }

    // MARK: Role → type name mapping

    private static func roleToTypeName(_ role: NSAccessibility.Role?) -> String {
        guard let role else { return "View" }
        switch role {
        case .button: return "Button"
        case .staticText: return "Text"
        case .image: return "Image"
        case .textField: return "TextField"
        case .textArea: return "TextEditor"
        case .checkBox: return "Toggle"
        case .radioButton: return "Picker (radio)"
        case .slider: return "Slider"
        case .list: return "List"
        case .table: return "List"
        case .outline: return "List (outline)"
        case .scrollArea: return "ScrollView"
        case .tabGroup: return "TabView"
        case .toolbar: return "Toolbar"
        case .link: return "Link"
        case .progressIndicator: return "ProgressView"
        case .group: return "Group/Stack"
        case .popUpButton: return "Menu/Picker"
        case .menuButton: return "Menu"
        case .splitGroup: return "SplitView"
        default: return role.rawValue
        }
    }

    private static func roleToTraits(_ role: NSAccessibility.Role?) -> [String] {
        guard let role else { return [] }
        switch role {
        case .button: return ["button"]
        case .staticText: return ["staticText"]
        case .image: return ["image"]
        case .link: return ["link"]
        case .checkBox: return ["toggle"]
        case .slider: return ["adjustable"]
        case .list, .table: return ["list"]
        case .tabGroup: return ["tabGroup"]
        default: return []
        }
    }

    /// Build a hierarchy path by walking the accessibility parent chain.
    private static func buildAccessibilityPath(from element: Any) -> String {
        var components: [String] = []
        var current: Any? = element

        while current != nil {
            let className = String(describing: type(of: current!))
            if isHostingView(className) {
                components.append("HostingView")
                break
            }

            // Try to get role via ObjC runtime
            if let obj = current as? NSObject {
                let roleSel = NSSelectorFromString("accessibilityRole")
                if obj.responds(to: roleSel),
                   let roleStr = obj.perform(roleSel)?.takeUnretainedValue() as? String {
                    let typeName = roleToTypeName(NSAccessibility.Role(rawValue: roleStr))
                    if typeName != "View" && !components.contains(typeName) {
                        components.append(typeName)
                    }
                }
            }

            // Walk up via NSAccessibilityElementProtocol.accessibilityParent()
            if let accessible = current as? NSAccessibilityElementProtocol {
                current = accessible.accessibilityParent()
            } else {
                break
            }
            if components.count >= 8 { break }
        }

        if components.isEmpty { return "View" }
        return components.reversed().joined(separator: " > ")
    }

    // MARK: Deep subview walk (fallback)

    static func deepestView(at windowPoint: CGPoint, in root: NSView) -> NSView {
        for subview in root.subviews.reversed() {
            guard !subview.isHidden, subview.alphaValue > 0.01 else { continue }
            if isOverlayView(subview) { continue }
            let subLocal = subview.convert(windowPoint, from: nil)
            guard subview.bounds.contains(subLocal) else { continue }
            return deepestView(at: windowPoint, in: subview)
        }
        return root
    }

    // MARK: View-based helpers

    fileprivate static func windowFrame(for view: NSView) -> CGRect {
        guard let window = view.window else { return view.frame }
        let frameInWindow = view.convert(view.bounds, to: nil)
        let windowHeight = window.contentView?.bounds.height ?? window.frame.height
        return CGRect(
            x: frameInWindow.origin.x,
            y: windowHeight - frameInWindow.origin.y - frameInWindow.height,
            width: frameInWindow.width,
            height: frameInWindow.height
        )
    }

    fileprivate static func inferSwiftUIType(from view: NSView, className: String) -> String {
        if view is NSButton { return "Button" }
        if view is NSImageView { return "Image" }
        if view is NSTextField {
            return (view as! NSTextField).isEditable ? "TextField" : "Text"
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

        if let match = inferFromClassName(className) { return match }

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
