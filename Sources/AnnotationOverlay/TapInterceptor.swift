import SwiftUI

/// Callback delivering the tap/click location (in window coords) and the hit-tested view.
typealias TapHandler = (_ windowPoint: CGPoint, _ hitView: PlatformView?) -> Void

// MARK: - iOS (UIKit)

#if canImport(UIKit)
import UIKit

/// A transparent UIView overlay that intercepts taps when annotation mode is active,
/// hit-tests through itself to find the underlying view, and reports back.
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

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return isActive
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard isActive, let window = self.window else { return }

        let pointInSelf = gesture.location(in: self)
        let windowPoint = convert(pointInSelf, to: nil)

        // Step out of hit-test, find the initial view, then drill to the deepest child.
        isUserInteractionEnabled = false
        let initialHit = window.hitTest(windowPoint, with: nil)
        isUserInteractionEnabled = true

        guard let root = initialHit, !isOwnOverlayView(root) else { return }

        let deepest = ViewInspector.deepestView(at: windowPoint, in: root)
        onTap?(windowPoint, deepest)
    }

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

// MARK: - macOS (AppKit)

#elseif canImport(AppKit)
import AppKit

/// A transparent NSView overlay that intercepts clicks when annotation mode is active,
/// walks the subview tree to find the deepest view under the cursor, and reports back.
struct TapInterceptorView: NSViewRepresentable {
    let isActive: Bool
    let onTap: TapHandler

    func makeNSView(context: Context) -> TapInterceptorNSView {
        let view = TapInterceptorNSView()
        view.onTap = onTap
        view.isActive = isActive
        return view
    }

    func updateNSView(_ nsView: TapInterceptorNSView, context: Context) {
        nsView.onTap = onTap
        nsView.isActive = isActive
    }
}

final class TapInterceptorNSView: NSView {
    var onTap: TapHandler?
    var isActive: Bool = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        click.numberOfClicksRequired = 1
        addGestureRecognizer(click)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isActive else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return isActive
    }

    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        guard isActive, let window = self.window, let contentView = window.contentView else { return }

        let pointInSelf = gesture.location(in: self)
        let windowPoint = convert(pointInSelf, to: nil)

        // Step out of hit-test, then walk the entire subview tree directly.
        // This avoids NSView.hitTest coordinate-space issues and finds
        // non-interactive SwiftUI elements that hitTest would skip.
        isActive = false
        let deepest = ViewInspector.deepestView(at: windowPoint, in: contentView)
        isActive = true

        if isOwnOverlayView(deepest) { return }

        // Convert to top-left origin for consistency with SwiftUI coordinates.
        let flippedY = contentView.bounds.height - windowPoint.y
        let normalizedPoint = CGPoint(x: windowPoint.x, y: flippedY)

        onTap?(normalizedPoint, deepest)
    }

    private func isOwnOverlayView(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let v = current {
            let id = v.accessibilityIdentifier()
            if id.hasPrefix("_annotationOverlay") {
                return true
            }
            current = v.superview
        }
        return false
    }
}

#endif
