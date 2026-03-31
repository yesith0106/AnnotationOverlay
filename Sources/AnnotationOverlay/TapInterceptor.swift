import SwiftUI
import UIKit

/// Callback delivering the tap location (in window coords) and the hit-tested UIView.
typealias TapHandler = (_ windowPoint: CGPoint, _ hitView: UIView?) -> Void

// MARK: - SwiftUI Bridge

/// A transparent UIView overlay that intercepts taps when annotation mode is active,
/// hit-tests through itself to find the underlying UIKit-backed view, and reports back.
struct TapInterceptorView: UIViewRepresentable {
    let isActive: Bool
    let onTap: TapHandler

    func makeUIView(context: Context) -> TapInterceptorUIView {
        let view = TapInterceptorUIView()
        view.onTap = onTap
        view.isActive = isActive
        return view
    }

    func updateUIView(_ uiView: TapInterceptorUIView, context: Context) {
        uiView.onTap = onTap
        uiView.isActive = isActive
    }
}

// MARK: - UIKit Tap View

/// The actual UIView that handles gesture recognition and hit-testing.
///
/// When `isActive` is true, this view claims all touches via `point(inside:with:)`.
/// On tap, it temporarily removes itself from the hit-test chain, asks the window
/// to find the real target underneath, then reports the result.
final class TapInterceptorUIView: UIView {
    var onTap: TapHandler?
    var isActive: Bool = false {
        didSet { isUserInteractionEnabled = isActive }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Only claim the touch when annotation mode is on.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return isActive
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard isActive, let window = self.window else { return }

        let pointInSelf = gesture.location(in: self)
        let windowPoint = convert(pointInSelf, to: nil)

        // Temporarily step out of the hit-test chain so the window
        // finds the real content view underneath.
        isUserInteractionEnabled = false
        let hitView = window.hitTest(windowPoint, with: nil)
        isUserInteractionEnabled = true

        // Ignore hits on our own overlay siblings (annotation markers, toolbar).
        // Those live in a SwiftUI overlay and have the tag `annotationOverlayTag`.
        if let hit = hitView, isOwnOverlayView(hit) {
            return
        }

        onTap?(windowPoint, hitView)
    }

    /// Check whether a view is part of our annotation overlay chrome.
    /// We tag overlay views via `accessibilityIdentifier` containing a known prefix.
    private func isOwnOverlayView(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let v = current {
            if let id = v.accessibilityIdentifier, id.hasPrefix("_annotationOverlay") {
                return true
            }
            current = v.superview
        }
        return false
    }
}
