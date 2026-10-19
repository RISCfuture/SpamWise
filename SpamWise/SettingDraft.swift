import SwiftUI

/**
 One setting edited through a pending value, so a burst of changes saves once.

 While it has no pending edit, the draft shows the persisted value, so it follows changes made
 elsewhere. An edit is saved once `delay` passes without another edit, or at once through
 ``commit()``. An edit that `accepts` rejects stays pending, and unsaved, until it is corrected.
 */
@MainActor
@Observable
final class SettingDraft<Value: Equatable & Sendable> {
  /// The edit not yet saved, if any.
  private(set) var edit: Value?
  @ObservationIgnored private let delay: Duration
  @ObservationIgnored private let persisted: @MainActor () -> Value
  @ObservationIgnored private let accepts: (Value) -> Bool
  @ObservationIgnored private let save: @MainActor (Value) -> Void
  /// The scheduled save of ``edit``, if one is waiting for `delay` to pass.
  @ObservationIgnored private(set) var scheduledSave: Task<Void, Never>?

  /// The pending edit, or else the persisted value; setting it schedules a save.
  var value: Value {
    get { edit ?? persisted() }
    set { change(to: newValue) }
  }
  /// Whether the shown value differs from the persisted one.
  var hasUnsavedEdit: Bool { edit != nil }
  /// Whether the shown value can be saved.
  var isAcceptable: Bool { accepts(value) }

  /**
   Creates a draft of one setting.

   - Parameters:
     - delay: How long the draft waits after the latest edit before saving it.
     - persisted: Reads the setting's current persisted value.
     - accepts: Whether a value can be saved; a rejected edit stays pending.
     - save: Persists an edit.
   */
  init(
    delay: Duration,
    persisted: @escaping @MainActor () -> Value,
    accepts: @escaping (Value) -> Bool = { _ in true },
    save: @escaping @MainActor (Value) -> Void
  ) {
    self.delay = delay
    self.persisted = persisted
    self.accepts = accepts
    self.save = save
  }

  /// Saves the pending edit now, if it is acceptable.
  func commit() {
    scheduledSave?.cancel()
    scheduledSave = nil
    saveEdit()
  }

  private func change(to value: Value) {
    scheduledSave?.cancel()
    scheduledSave = nil
    guard value != persisted() else {
      edit = nil
      return
    }
    edit = value
    guard accepts(value) else { return }
    scheduledSave = Task { [weak self, delay] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.saveEdit()
    }
  }

  private func saveEdit() {
    guard let edit, accepts(edit) else { return }
    save(edit)
    self.edit = nil
  }
}

extension View {
  /// Commits `draft` when editing ends: on Return, when focus leaves the field, or on disappear.
  func commitsDraft<Value>(_ draft: SettingDraft<Value>) -> some View {
    commitsEdits(draft.commit)
  }

  /// Runs `commit` when editing ends: on Return, when focus leaves the field, or on disappear.
  func commitsEdits(_ commit: @escaping () -> Void) -> some View {
    modifier(DraftCommit(commit: commit))
  }
}

private struct DraftCommit: ViewModifier {
  let commit: () -> Void
  @FocusState private var isFocused: Bool

  func body(content: Content) -> some View {
    content
      .focused($isFocused)
      .onSubmit(commit)
      .onChange(of: isFocused) { _, focused in if !focused { commit() } }
      .onDisappear(perform: commit)
  }
}
