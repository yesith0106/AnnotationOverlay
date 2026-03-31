import SwiftUI

/// The main annotation overlay that wraps user content.
///
/// Adds a transparent tap interceptor, visual annotation markers,
/// a note editor, and a floating toolbar on top of the wrapped content.
struct AnnotationOverlayView<Content: View>: View {
    let content: Content
    let screenName: String
    @Bindable var store: AnnotationStore

    @State private var overlayOrigin: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // 1. User's actual content
                content
                    .frame(width: geo.size.width, height: geo.size.height)

                // 2. Annotation markers & highlights (non-interactive)
                annotationMarkers(in: geo)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("_annotationOverlayMarkers")

                // 3. Tap interceptor (transparent platform overlay)
                TapInterceptorView(
                    isActive: store.isAnnotationMode,
                    onTap: { windowPoint, hitView in
                        handleTap(windowPoint: windowPoint, hitView: hitView, in: geo)
                    }
                )

                // 4. Note editor popover (interactive)
                if let editingID = store.editingAnnotationID,
                   let annotation = store.annotations.first(where: { $0.id == editingID }) {
                    noteEditor(for: annotation, in: geo)
                        .accessibilityIdentifier("_annotationOverlayEditor")
                }

                // 5. Floating toolbar
                floatingToolbar()
                    .accessibilityIdentifier("_annotationOverlayToolbar")

                // 6. Toast message
                if let toast = store.toastMessage {
                    toastView(toast)
                }
            }
            .onAppear {
                let frame = geo.frame(in: .global)
                overlayOrigin = frame.origin
            }
        }
    }

    // MARK: - Tap Handler

    private func handleTap(windowPoint: CGPoint, hitView: PlatformView?, in geo: GeometryProxy) {
        guard let hitView else { return }

        // Check if tap is near an existing annotation — if so, edit it
        let localPoint = CGPoint(
            x: windowPoint.x - overlayOrigin.x,
            y: windowPoint.y - overlayOrigin.y
        )
        for annotation in store.annotations {
            let markerCenter = CGPoint(
                x: annotation.metadata.windowFrame.minX - overlayOrigin.x,
                y: annotation.metadata.windowFrame.minY - overlayOrigin.y
            )
            if distance(localPoint, markerCenter) < 30 {
                store.editingAnnotationID = annotation.id
                return
            }
        }

        let metadata = ViewInspector.extractMetadata(from: hitView)
        store.addAnnotation(metadata: metadata)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: - Annotation Markers

    @ViewBuilder
    private func annotationMarkers(in geo: GeometryProxy) -> some View {
        ForEach(store.annotations) { annotation in
            let frame = annotation.metadata.windowFrame
            let localX = frame.origin.x - overlayOrigin.x
            let localY = frame.origin.y - overlayOrigin.y

            // Highlight rectangle
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.blue.opacity(0.8), lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.08))
                )
                .frame(width: frame.width, height: frame.height)
                .position(
                    x: localX + frame.width / 2,
                    y: localY + frame.height / 2
                )

            // Numbered marker circle (top-left of element)
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                Text("\(annotation.number)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .position(x: localX, y: localY)
        }
    }

    // MARK: - Note Editor

    @ViewBuilder
    private func noteEditor(for annotation: Annotation, in geo: GeometryProxy) -> some View {
        let frame = annotation.metadata.windowFrame
        let elementBottom = frame.maxY - overlayOrigin.y
        let elementCenterX = frame.midX - overlayOrigin.x

        let editorWidth: CGFloat = min(280, geo.size.width - 32)
        let editorX = clamp(elementCenterX, min: editorWidth / 2 + 16, max: geo.size.width - editorWidth / 2 - 16)
        let editorY: CGFloat = {
            let preferred = elementBottom + 12
            if preferred + 120 > geo.size.height {
                return (frame.minY - overlayOrigin.y) - 80
            }
            return preferred + 60
        }()

        NoteEditorCard(
            annotation: annotation,
            onUpdateNote: { note in
                store.updateNote(for: annotation.id, note: note)
            },
            onDone: {
                store.finishEditing()
            },
            onDelete: {
                store.removeAnnotation(id: annotation.id)
            }
        )
        .frame(width: editorWidth)
        .position(x: editorX, y: editorY)
        .transition(.scale.combined(with: .opacity))
    }

    private func clamp(_ value: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        Swift.min(hi, Swift.max(lo, value))
    }

    // MARK: - Floating Toolbar

    @ViewBuilder
    private func floatingToolbar() -> some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 0) {
                Spacer()
                FloatingToolbarView(
                    store: store,
                    screenName: screenName
                )
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private func toastView(_ message: String) -> some View {
        VStack {
            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(.black.opacity(0.8)))
                .padding(.top, 60)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeOut(duration: 0.3)) {
                    store.toastMessage = nil
                }
            }
        }
    }
}

// MARK: - Note Editor Card

private struct NoteEditorCard: View {
    let annotation: Annotation
    let onUpdateNote: (String) -> Void
    let onDone: () -> Void
    let onDelete: () -> Void

    @State private var noteText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Label("\(annotation.metadata.viewType)", systemImage: "scope")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Text("#\(annotation.number)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Metadata summary
            if let id = annotation.metadata.accessibilityIdentifier {
                Text("ID: \(id)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Note input
            TextField("Add a note for Claude...", text: $noteText, axis: .vertical)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($isFocused)
                .onSubmit {
                    onUpdateNote(noteText)
                    onDone()
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.ultraThinMaterial)
                )

            // Actions
            HStack(spacing: 12) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.8))

                Spacer()

                Button {
                    onUpdateNote(noteText)
                    onDone()
                } label: {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.blue))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        )
        .onAppear {
            noteText = annotation.note
            isFocused = true
        }
    }
}

// MARK: - Floating Toolbar

private struct FloatingToolbarView: View {
    @Bindable var store: AnnotationStore
    let screenName: String

    var body: some View {
        HStack(spacing: 2) {
            // Annotation mode toggle
            toolbarButton(
                icon: "pin.fill",
                isActive: store.isAnnotationMode,
                activeColor: .blue
            ) {
                withAnimation(.spring(duration: 0.3)) {
                    store.isAnnotationMode.toggle()
                    if !store.isAnnotationMode {
                        store.finishEditing()
                    }
                }
            }

            if store.isAnnotationMode || !store.annotations.isEmpty {
                // Annotation count badge
                if !store.annotations.isEmpty {
                    Text("\(store.annotations.count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.blue))
                        .padding(.horizontal, 4)
                }

                // Copy as Markdown
                toolbarButton(icon: "doc.on.clipboard", isActive: false) {
                    guard !store.annotations.isEmpty else { return }
                    MarkdownExporter.copyToClipboard(
                        annotations: store.annotations,
                        screenName: screenName
                    )
                    withAnimation(.spring(duration: 0.3)) {
                        store.showToast("Copied \(store.annotations.count) annotation(s) to clipboard")
                    }
                }

                // Copy as JSON
                toolbarButton(icon: "curlybraces", isActive: false) {
                    guard !store.annotations.isEmpty else { return }
                    let json = MarkdownExporter.exportJSON(annotations: store.annotations)
                    MarkdownExporter.copyString(json)
                    withAnimation(.spring(duration: 0.3)) {
                        store.showToast("Copied JSON to clipboard")
                    }
                }

                // Clear all
                toolbarButton(icon: "trash", isActive: false, activeColor: .red) {
                    withAnimation(.spring(duration: 0.3)) {
                        store.clearAll()
                    }
                }
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .animation(.spring(duration: 0.3), value: store.isAnnotationMode)
        .animation(.spring(duration: 0.3), value: store.annotations.count)
    }

    @ViewBuilder
    private func toolbarButton(
        icon: String,
        isActive: Bool,
        activeColor: Color = .blue,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isActive ? activeColor : .primary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isActive ? activeColor.opacity(0.15) : .clear)
                )
        }
        .buttonStyle(.plain)
    }
}
