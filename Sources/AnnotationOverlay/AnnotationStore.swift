import SwiftUI
import Combine

/// Central state for the annotation overlay session.
///
/// Manages the list of annotations, the active/editing state,
/// and the annotation mode toggle.
public final class AnnotationStore: ObservableObject {

    // MARK: - Published State

    /// All annotations in the current session, ordered by creation.
    @Published public private(set) var annotations: [Annotation] = []

    /// Whether annotation mode is active (taps are intercepted).
    @Published public var isAnnotationMode: Bool = false

    /// The annotation currently being edited (note input visible).
    @Published public var editingAnnotationID: UUID? = nil

    /// Brief feedback message shown after clipboard copy, etc.
    @Published public var toastMessage: String? = nil

    // MARK: - Private

    private var nextNumber: Int = 1

    // MARK: - Init

    public init() {}

    // MARK: - Mutations

    /// Create a new annotation from captured view metadata.
    @discardableResult
    public func addAnnotation(metadata: ViewMetadata) -> Annotation {
        let annotation = Annotation(number: nextNumber, metadata: metadata)
        nextNumber += 1
        annotations.append(annotation)
        editingAnnotationID = annotation.id
        return annotation
    }

    /// Update the note text on an existing annotation.
    public func updateNote(for id: UUID, note: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].note = note
    }

    /// Remove a single annotation by ID.
    public func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
        if editingAnnotationID == id {
            editingAnnotationID = nil
        }
    }

    /// Clear all annotations and reset numbering.
    public func clearAll() {
        annotations.removeAll()
        editingAnnotationID = nil
        nextNumber = 1
    }

    /// Dismiss the note editor without removing the annotation.
    public func finishEditing() {
        editingAnnotationID = nil
    }

    /// Show a brief toast message that auto-dismisses.
    public func showToast(_ message: String) {
        toastMessage = message
    }
}
