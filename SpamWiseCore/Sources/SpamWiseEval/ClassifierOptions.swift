import ArgumentParser
import Evaluation
import Foundation
import SpamWiseCore

/// The classifier an evaluation run uses: the offline mock or one selectable provider model.
enum EvaluationModel: Equatable, CustomStringConvertible, ExpressibleByArgument {
  /// Deterministic offline verdicts that exercise plumbing, never model quality.
  case mock
  /// One explicitly selected provider model, without fallback.
  case provider(ModelIdentifier)

  private static let mockArgument = "mock"

  static var allValueStrings: [String] {
    [mockArgument] + ModelIdentifier.allCases.filter(isSelectable).map(\.rawValue)
  }

  var description: String {
    switch self {
      case .mock: Self.mockArgument
      case .provider(let model): model.rawValue
    }
  }

  var defaultValueDescription: String { description }

  /// Spending reserved before each uncached request; nil when the model has no API charge.
  var reservationUSD: Double? {
    guard case .provider(let model) = self else { return nil }
    return model.reservationUSD
  }

  init?(argument: String) {
    if argument == Self.mockArgument {
      self = .mock
    } else if let model = ModelIdentifier(rawValue: argument), Self.isSelectable(model) {
      self = .provider(model)
    } else {
      return nil
    }
  }

  private static func isSelectable(_ model: ModelIdentifier) -> Bool {
    model.backend != .privateCloudCompute
  }
}

/// Classifier selection, spending and response-cache options shared by labeled evaluation runs.
struct ClassifierOptions: ParsableArguments {
  private static let liveVariable = "SPAMWISE_LIVE_API"
  private static let commandLineSource = "command-line override"

  @Option(help: "Classifier model.")
  var model: EvaluationModel = .mock

  @Option(
    help: """
      Filtering strength whose thresholds set the reported labels; defaults to the --state \
      snapshot's, which defaults to balanced.
      """
  )
  var strength: FilteringStrength?

  @Option(help: "Directory of validated responses reused across runs.")
  var cache = ".spamwise-eval-cache"

  @Option(help: "Mock verdicts keyed by raw-message hash; mock model only.")
  var mockResponses: String?

  @Option(help: "Evaluation budget ledger, never the app’s store by default; paid models only.")
  var budgetStore: String?

  @Option(help: "Spending ceiling in USD to record in the budget ledger, keeping commitments.")
  var budgetLimit: Double?

  @Option(
    help: """
      Spending reserved before each uncached request, in USD: at most the model's default and at \
      least the cost of a full-size request at its standard rates.
      """
  )
  var reservation: Double?

  @Option(help: "Uncached input rate override, in USD per million tokens.")
  var inputPrice: Double?

  @Option(help: "Output rate override, in USD per million tokens.")
  var outputPrice: Double?

  @Option(help: "Cached input rate override, in USD per million tokens.")
  var cachePrice: Double?

  /// Cache identity, distinguishing mock response files from one another.
  var identity: String {
    get throws {
      guard let mockResponses else { return model.description }
      return model.description + ":"
        + stableHash(try Data(contentsOf: URL(filePath: mockResponses)))
    }
  }

  /// Rates for the report's cost estimate, with any overrides applied; nil for the mock.
  var pricing: ModelTokenPricing? {
    guard case .provider(let model) = model else { return nil }
    let standard = ModelTokenPricing.rates(for: model)
    return ModelTokenPricing(
      input: inputPrice ?? standard.input,
      output: outputPrice ?? standard.output,
      cached: cachePrice ?? standard.cached,
      source: pricingOverridden ? Self.commandLineSource : standard.source,
      verified: standard.verified
    )
  }

  private var pricingOverridden: Bool {
    [inputPrice, outputPrice, cachePrice].contains { $0 != nil }
  }

  private static func apiKey(for backend: ModelBackend) throws -> String {
    guard let variable = apiKeyVariable(for: backend) else { return "" }
    guard let key = ProcessInfo.processInfo.environment[variable], !key.isEmpty else {
      throw CorpusRunError.missingKey(variable: variable)
    }
    return key
  }

  private static func apiKeyVariable(for backend: ModelBackend) -> String? {
    switch backend {
      case .claude: "ANTHROPIC_API_KEY"
      case .openAI: "OPENAI_API_KEY"
      case .gemini: "GEMINI_API_KEY"
      case .onDevice, .privateCloudCompute: nil
    }
  }

  func validate() throws {
    try requireProviderOnlyOptions()
    try requireBudgetLedger()
    try requireValidAmounts()
    try requireBoundedReservation()
  }

  /// Builds the selected classifier, refusing live calls without explicit authorization.
  func classifier() async throws -> any Classifier {
    switch model {
      case .mock: try mockClassifier()
      case .provider(let model): try await providerClassifier(model)
    }
  }

  private func requireProviderOnlyOptions() throws {
    if model == .mock {
      let providerOnly = [
        budgetStore != nil, budgetLimit != nil, reservation != nil, pricingOverridden
      ]
      guard !providerOnly.contains(true) else {
        throw ValidationError(
          String(
            localized: "Budget and price options apply only to provider models.",
            bundle: .module
          )
        )
      }
    } else if mockResponses != nil {
      throw ValidationError(
        String(localized: "--mock-responses requires --model mock.", bundle: .module)
      )
    }
  }

  private func requireBudgetLedger() throws {
    if budgetLimit != nil, budgetStore == nil {
      throw ValidationError(
        String(localized: "--budget-limit requires --budget-store.", bundle: .module)
      )
    }
    if model.reservationUSD != nil, budgetStore == nil {
      throw ValidationError(
        String(localized: "Paid models require --budget-store PATH.", bundle: .module)
      )
    }
  }

  private func requireValidAmounts() throws {
    let amounts = [
      ("--budget-limit", budgetLimit), ("--input-price", inputPrice),
      ("--output-price", outputPrice), ("--cache-price", cachePrice)
    ]
    for case let (flag, amount?) in amounts where !(amount.isFinite && amount >= 0) {
      throw ValidationError(
        String(localized: "\(flag) must be a nonnegative amount in USD.", bundle: .module)
      )
    }
  }

  /// Refuses a reservation that could fall short of a request's cost or exceed the default.
  private func requireBoundedReservation() throws {
    guard let reservation, case .provider(let model) = model,
      let standard = model.reservationUSD
    else { return }
    let minimum = ModelTokenPricing.rates(for: model).maximumRequestCost
    guard reservation >= minimum, reservation <= standard else {
      throw ValidationError(
        String(
          localized:
            "--reservation must be from \(minimum.formatted()) to \(standard.formatted()) USD.",
          bundle: .module
        )
      )
    }
  }

  private func mockClassifier() throws -> any Classifier {
    guard let mockResponses else {
      return MockClassifier(
        verdict: .init(label: .review, confidence: 0, reason: "Offline mock: no predictive model")
      )
    }
    let responses = try JSONDecoder().decode(
      [String: Verdict].self,
      from: Data(contentsOf: URL(filePath: mockResponses))
    )
    return MockClassifier { input in
      guard let verdict = responses[input.message.hash] else {
        throw CorpusRunError.missingMock(hash: input.message.hash)
      }
      return verdict
    }
  }

  private func providerClassifier(_ model: ModelIdentifier) async throws -> any Classifier {
    guard ProcessInfo.processInfo.environment[Self.liveVariable] == "1" else {
      throw CorpusRunError.liveDisabled(variable: Self.liveVariable)
    }
    guard let reservationUSD = model.reservationUSD else {
      return ClassifierFactory.make(model, credential: { "" })
    }
    let key = try Self.apiKey(for: model.backend)
    return BudgetedClassifier(
      ClassifierFactory.make(model, credential: { key }),
      store: try await EvaluationBudget.ledgerStore(
        at: budgetStore.map { URL(filePath: $0) },
        limitUSD: budgetLimit
      ),
      upperBoundUSD: reservation ?? reservationUSD
    )
  }
}
