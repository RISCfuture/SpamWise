import SwiftUI
import SpamWiseCore

/// The content of each Activity sheet, given the models it needs.
struct ActivitySheetView: View {
  let sheet: ActivitySheet
  let model: AppModel

  var body: some View {
    switch sheet {
      case .digest:
        ReviewDigestView(
          activity: model.activity,
          shared: model.shared,
          corrections: model.corrections,
          messages: model.messages
        )
      case .selectionCorrections:
        CorrectionResultsView(corrections: model.corrections)
      case .junkReview:
        MailReviewView(review: model.junkReview)
      case .messagePreview(let preview):
        MessagePreviewSheet(preview: preview)
      case .statistics:
        ActivityStatisticsView(activity: model.activity, shared: model.shared)
      case .audit:
        AuditTrailView(shared: model.shared)
      case .corpus:
        CorpusView(corpus: model.corpus)
      case .dateFilter:
        @Bindable var activity = model.activity
        ActivityDateFilterView(query: $activity.query)
    }
  }
}
