import SwiftUI
import SpamWiseCore

/**
 Stands in for content that needs saved settings until they are read, so no control shows
 defaults it would save over them.

 A failed read offers Try Again while storage is open; when storage couldn’t be opened at all, the
 failure says what to do instead.
 */
struct StorageLoadingView: View {
  let shared: SharedStateModel
  /// Names what is unavailable when reading fails.
  let unavailableTitle: LocalizedStringKey
  /// Says what is loading while the first read runs.
  let loadingTitle: LocalizedStringKey

  var body: some View {
    if case .failure(let failure) = shared.storageStatus {
      ContentUnavailableView {
        Label(unavailableTitle, systemImage: "exclamationmark.triangle")
      } description: {
        Text(failure.description)
      } actions: {
        if shared.store != nil {
          Button("Try Again") { Task { await shared.refresh() } }
            .accessibilityIdentifier("storage.retry")
        }
      }
    } else {
      ProgressView(loadingTitle)
    }
  }
}

#Preview("Loading") {
  StorageLoadingView(
    shared: SharedStateModel(store: nil, reportsMissingStore: false),
    unavailableTitle: "Settings Unavailable",
    loadingTitle: "Loading settings…"
  )
}
#Preview("Unavailable") {
  StorageLoadingView(
    shared: SharedStateModel(store: nil),
    unavailableTitle: "SpamWise Data Unavailable",
    loadingTitle: "Loading settings…"
  )
}
