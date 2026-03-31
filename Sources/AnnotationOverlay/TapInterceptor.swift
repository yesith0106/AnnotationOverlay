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

        isUserInteractionEnabled = false
        let hitView = window.hitTest(windowPoint, with: nil)
        isUserInteractionEnabled = true

        if let hit = hitView, isOwnOverlayView(hit) { return }

        onTap?(windowPoint, hitView)
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
/// hit-tests through itself to find the underlying view, and reports back.
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

    // Only claim the click when annotation mode is active.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isActive else { return nil }
        return super.hitTest(point)
    }

    // Accept first mouse so clicks register even when the window isn't focused.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return isActive
    }

    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        guard isActive, let window = self.window, let contentView = window.contentView else { return }

        let pointInSelf = gesture.location(in: self)
        let windowPoint = convert(pointInSelf, to: nil)

        // Temporarily hide from hit-testing to find the real view underneath.
        isActive = false
        let contentPoint = contentView.convert(windowPoint, from: nil)
        let hitView = contentView.hitTest(contentPoint)
        isActive = true

        if let hit = hitView, isOwnOverlayView(hit) { return }

        // Convert to top-left origin for consistency with SwiftUI coordinates.
        let flippedY = contentView.bounds.height - windowPoint.y
        let normalizedPoint = CGPoint(x: windowPoint.x, y: flippedY)

        onTap?(normalizedPoint, hitView)
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
