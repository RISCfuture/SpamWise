import SwiftUI
import SpamWiseCore

extension ThreatAssessment {
  /// Whether a detector ran, so the findings say more than “not assessed”.
  var wasAssessed: Bool {
    detector != nil || findings.contains { $0.status != .unknown }
  }
}

/// What a threat detector found, and which parts of the message it checked.
struct ThreatAssessmentView: View {
  let assessment: ThreatAssessment

  private var findings: [ThreatFinding] {
    assessment.findings.filter { $0.status == .detected }
  }

  var body: some View {
    if findings.isEmpty {
      Text("No threats found in the parts that were checked")
        .accessibilityIdentifier("threats.status")
    }
    ForEach(findings, id: \.kind) { finding in
      LabeledContent(finding.kind.localizedTitle, value: finding.reason)
    }
    DisclosureGroup("What was checked") {
      ForEach(ThreatKind.allCases, id: \.self) { kind in
        LabeledContent(kind.localizedTitle) {
          if let finding = assessment.finding(for: kind), finding.status != .unknown {
            Text(finding.coverage)
          } else {
            Text("Not checked")
          }
        }
      }
      if let detector = assessment.detector {
        LabeledContent("Detector", value: detector.implementation)
        LabeledContent("Model", value: detector.model)
      }
    }
  }
}

private extension ThreatKind {
  var localizedTitle: String {
    switch self {
      case .spam: String(localized: "Spam")
      case .phishing: String(localized: "Phishing")
      case .spearphishing: String(localized: "Spearphishing")
      case .fraud: String(localized: "Fraud")
      case .malware: String(localized: "Malware")
    }
  }
}

#Preview("Threat finding") {
  if let assessment = PreviewHelper.threatAssessment {
    Form { ThreatAssessmentView(assessment: assessment) }
  }
}
