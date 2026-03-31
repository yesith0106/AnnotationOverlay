import SwiftUI

// MARK: - Public API

extension View {
    /// Wraps this view with an annotation overlay for debug sessions.
    ///
    /// When annotation mode is activated via the floating toolbar, tapping any
    /// element captures its metadata (type, accessibility info, frame, hierarchy path).
    /// Add notes, then copy structured markdown to paste into Claude Code for precise fixes.
    ///
    /// Usage:
    /// ```swift
    /// #if DEBUG
    /// import AnnotationOverlay
    /// #endif
    ///
    /// struct ContentView: View {
    ///     var body: some View {
    ///         MyActualContent()
    ///             #if DEBUG
    ///             .annotatable()
    ///             #endif
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - screenName: A label for this screen, included in the markdown output header.
    ///                 Defaults to `"Screen"`.
    ///   - store: An optional shared `AnnotationStore`. If omitted, a new store is
    ///            created automatically. Pass your own to share state across views
    ///            or access annotations programmatically.
    /// - Returns: The view wrapped with the annotation overlay.
    public func annotatable(
        screenName: String = "Screen",
        store: AnnotationStore? = nil
    ) -> some View {
        modifier(AnnotatableModifier(screenName: screenName, externalStore: store))
    }
}

// MARK: - View Modifier

private struct AnnotatableModifier: ViewModifier {
    let screenName: String
    let externalStore: AnnotationStore?

    @State private var internalStore = AnnotationStore()

    private var store: AnnotationStore {
        externalStore ?? internalStore
    }

    func body(content: Content) -> some View {
        AnnotationOverlayView(
            content: content,
            screenName: screenName,
            store: store
        )
    }
}

// MARK: - Wrapper Alternative

/// A wrapper view that provides the annotation overlay.
///
/// Use this as an alternative to the `.annotatable()` modifier when you prefer
/// an explicit wrapper:
///
/// ```swift
/// #if DEBUG
/// AnnotationOverlay(screenName: "Settings") {
///     SettingsView()
/// }
/// #else
/// SettingsView()
/// #endif
/// ```
public struct AnnotationOverlay<Content: View>: View {
    private let content: Content
    private let screenName: String
    @State private var store = AnnotationStore()

    public init(
        screenName: String = "Screen",
        @ViewBuilder content: () -> Content
    ) {
        self.screenName = screenName
        self.content = content()
    }

    public var body: some View {
        AnnotationOverlayView(
            content: content,
            screenName: screenName,
            store: store
        )
    }
}
