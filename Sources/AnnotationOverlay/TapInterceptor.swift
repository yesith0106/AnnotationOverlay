import SwiftUI

/// Callback delivering the tap/click location (in overlay coords) and extracted metadata.
typealias TapHandler = (_ point: CGPoint, _ metadata: ViewMetadata?) -> Void

// MARK: - iOS (UIKit)

#if canImport(UIKit)
import UIKit

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

        // Step out of hit-test chain, find metadata via accessibility + view hierarchy.
        isUserInteractionEnabled = false
        let metadata = ViewInspector.findMetadata(at: windowPoint, in: window)
        isUserInteractionEnabled = true

        onTap?(windowPoint, metadata)
    }
}

// MARK: - macOS (AppKit)

#elseif canImport(AppKit)
import AppKit

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

        // Step out of hit-test, then find metadata via accessibility + view hierarchy.
        isActive = false
        let metadata = ViewInspector.findMetadata(at: windowPoint, in: window)
        isActive = true

        // Convert to top-left origin for SwiftUI coordinate consistency.
        let flippedY = contentView.bounds.height - windowPoint.y
        let normalizedPoint = CGPoint(x: windowPoint.x, y: flippedY)

        onTap?(normalizedPoint, metadata)
    }
}

#endif
