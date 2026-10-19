import SwiftUI
import SpamWiseCore

/**
 Stands in for content that needs saved settings until they are read, so no control shows
 defaults it would save over them.

 A failed read offers Try Again while storage is open and might be read; when storage couldn’t be
 opened at all, or a newer version of SpamWise saved it, the failure says what to do instead.
 */
struct StorageLoadingView: View {
  let shared: SharedStateModel
  /// Names what is unavailable when reading fails.
  let unavailableTitle: LocalizedStringKey
  /// Says what is loading while the first read runs.
  let loadingTitle: LocalizedStringKey

  private var failureTitle: LocalizedStringKey {
    shared.storedStateError == .newerVersion ? "Data Saved by a Newer Version" : unavailableTitle
  }

  var body: some View {
    if case .failure(let failure) = shared.storageStatus {
      ContentUnavailableView {
        Label(failureTitle, systemImage: "exclamationmark.triangle")
      } description: {
        Text(failure.description)
      } actions: {
        if shared.canRetryLoading {
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
