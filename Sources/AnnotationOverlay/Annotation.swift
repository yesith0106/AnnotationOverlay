import Foundation

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

/// Metadata captured from a tapped UI element's backing platform view.
public struct ViewMetadata {
    /// Inferred SwiftUI view type (e.g. "Button", "Text", "Image").
    public let viewType: String

    /// The element's accessibility identifier, if set.
    public let accessibilityIdentifier: String?

    /// The element's accessibility label, if set.
    public let accessibilityLabel: String?

    /// Platform-agnostic accessibility trait names (e.g. "button", "image", "header").
    public let accessibilityTraits: [String]

    /// Frame in the element's parent coordinate space.
    public let frame: CGRect

    /// Frame in window (screen) coordinates.
    public let windowFrame: CGRect

    /// Reconstructed view hierarchy path (e.g. "NavigationStack > VStack > Button").
    public let viewPath: String

    /// The raw platform class name, for advanced debugging.
    public let rawClassName: String
}

// MARK: - Accessibility Traits Description

extension ViewMetadata {
    /// Human-readable description of the element's accessibility traits.
    public var traitsDescription: String {
        accessibilityTraits.isEmpty ? "none" : accessibilityTraits.joined(separator: ", ")
    }
}
