import SwiftUI

// MARK: - Annotation

/// A single annotation placed on a UI element during a debug session.
public struct Annotation: Identifiable {
    public let id = UUID()
    public let number: Int
    public let metadata: ViewMetadata
    public var note: String
    public let timestamp: Date

    public init(number: Int, metadata: ViewMetadata, note: String = "") {
        self.number = number
        self.metadata = metadata
        self.note = note
        self.timestamp = Date()
    }
}

// MARK: - ViewMetadata

/// Metadata captured from a tapped UI element's backing UIKit view.
public struct ViewMetadata {
    /// Inferred SwiftUI view type (e.g. "Button", "Text", "Image").
    public let viewType: String

    /// The element's `accessibilityIdentifier`, if set.
    public let accessibilityIdentifier: String?

    /// The element's `accessibilityLabel`, if set.
    public let accessibilityLabel: String?

    /// Raw accessibility traits on the element.
    public let accessibilityTraits: UIAccessibilityTraits

    /// Frame in the element's parent coordinate space.
    public let frame: CGRect

    /// Frame in window (screen) coordinates.
    public let windowFrame: CGRect

    /// Reconstructed view hierarchy path (e.g. "NavigationStack > VStack > Button").
    public let viewPath: String

    /// The raw UIKit class name, for advanced debugging.
    public let rawClassName: String
}

// MARK: - Accessibility Traits Description

extension ViewMetadata {
    /// Human-readable description of the element's accessibility traits.
    public var traitsDescription: String {
        var parts: [String] = []
        if accessibilityTraits.contains(.button) { parts.append("button") }
        if accessibilityTraits.contains(.link) { parts.append("link") }
        if accessibilityTraits.contains(.image) { parts.append("image") }
        if accessibilityTraits.contains(.header) { parts.append("header") }
        if accessibilityTraits.contains(.staticText) { parts.append("staticText") }
        if accessibilityTraits.contains(.searchField) { parts.append("searchField") }
        if accessibilityTraits.contains(.adjustable) { parts.append("adjustable") }
        if accessibilityTraits.contains(.selected) { parts.append("selected") }
        if accessibilityTraits.contains(.notEnabled) { parts.append("notEnabled") }
        if accessibilityTraits.contains(.updatesFrequently) { parts.append("updatesFrequently") }
        if accessibilityTraits.contains(.summaryElement) { parts.append("summaryElement") }
        if accessibilityTraits.contains(.tabBar) { parts.append("tabBar") }
        return parts.isEmpty ? "none" : parts.joined(separator: ", ")
    }
}
