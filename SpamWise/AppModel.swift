public import Observation
import SwiftUI
import AppIntents
import SpamWiseCore
import MailIntegration

/**
 The feature models behind every SpamWise window, menu and App Intent.

 Each feature model receives only the services and models it depends on; views take the narrow
 model they need. This type composes them and runs the background monitor that keeps shared
 state current and starts automatic mail checks.
 */
@MainActor @Observable public final class AppModel {
  private static let monitorInterval: Duration = .seconds(3)
  let services: AppServices
  let shared: SharedStateModel
  let settings: SettingsModel
  let router = ActivityRouter()
  let mail: MailConnectionModel
  let imap: IMAPConnectionModel
  let relationships: RelationshipsModel
  let scanning: ScanCoordinator
  let activity: ActivityModel
  let corrections: CorrectionsModel
  let junkReview: JunkReviewModel
  let messages: MessageAccessModel
  let rules: RulesModel
  let folders: FolderPlansModel
  let olderMail: OlderMailModel
  let corpus: CorpusModel
  let backup: BackupModel
  let notifications: NotificationsModel
  let credentials: CredentialsModel
  /// A background problem outside any user operation, such as a fixture that failed to load.
  private(set) var backgroundFailure: OperationFailure?
  @ObservationIgnored private var monitoring: Task<Void, Never>?

  /// Whether the user can act on mail: setup is finished and shared storage is open.
  var canCorrectMail: Bool { shared.settings.onboardingComplete && services.storageReady }

  /// Creates the models over `services`; without a store, Activity shows `activityFixtures`.
  init(services: AppServices, activityFixtures: [DecisionRecord] = []) {
    self.services = services
    let shared = SharedStateModel(store: services.store, reportsMissingStore: !services.uiTesting)
    self.shared = shared
    settings = SettingsModel(shared: shared)
    mail = MailConnectionModel(services: services, shared: shared)
    imap = IMAPConnectionModel(services: services, shared: shared)
    relationships = RelationshipsModel(services: services, shared: shared)
    scanning = ScanCoordinator(
      services: services,
      shared: shared,
      mail: mail,
      relationships: relationships
    )
    activity =
      services.store.map { ActivityModel(store: $0, shared: shared) }
      ?? ActivityModel(fixtures: activityFixtures, shared: shared)
    corrections = CorrectionsModel(services: services)
    junkReview = JunkReviewModel(services: services, mail: mail, shared: shared)
    messages = MessageAccessModel(services: services)
    rules = RulesModel(services: services, shared: shared)
    folders = FolderPlansModel(services: services, shared: shared, mail: mail)
    olderMail = OlderMailModel(services: services, shared: shared)
    corpus = CorpusModel(services: services, shared: shared)
    backup = BackupModel(services: services)
    notifications = NotificationsModel(services: services, shared: shared)
    credentials = CredentialsModel(services: services)
  }

  /**
   Creates the model a launched app runs on, makes it available to App Intents
   and starts monitoring Mail.

   Call this once, from the edition's `App` initializer.
   */
  public static func launch() -> AppModel {
    let model = AppModel(services: .launched())
    unsafe AppDependencyManager.shared.add(dependency: model)
    model.startMonitoring()
    return model
  }

  /// Finishes setup and starts automatic filtering from now for the accounts in scope.
  func finishSetup() {
    settings.completeOnboarding()
    let scope = shared.settings.mailOptions.accountIDs
    scanning.startInboxFiltering(
      for: mail.accounts.filter { scope?.contains($0.id) ?? true },
      replacing: false
    )
  }

  /// Opens `url` from the Mail rule script or a notification.
  func handle(_ url: URL) {
    guard url.scheme == "spamwise" else { return }
    switch url.host {
      case "check-inbox": scanning.requestInboxCheck()
      case "review": router.present(.digest)
      default: return
    }
  }
}

extension AppModel {
  private var canMonitorMail: Bool { !services.uiTesting && shared.settings.onboardingComplete }

  func startMonitoring() {
    guard monitoring == nil else { return }
    monitoring = Task { [self] in
      await withDiscardingTaskGroup { group in
        if !services.uiTesting { group.addTask { await self.scanning.monitorNetwork() } }
        await monitor()
      }
    }
  }

  private func monitor() async {
    await seedUITestFixture()
    await shared.refresh()
    while !Task.isCancelled {
      try? await Task.sleep(for: Self.monitorInterval)
      guard !Task.isCancelled else { return }
      await shared.refresh()
      await mail.refreshAutomationStatus()
      guard canMonitorMail else { continue }
      await notifications.deliverIfEnabled()
      await relationships.refreshContactsIfDue()
      scanning.scanIfDue()
    }
  }

  private func seedUITestFixture() async {
    #if DEBUG
      guard services.uiTesting, let store = services.store else { return }
      do {
        try await UITestFixture.seed(arguments: ProcessInfo.processInfo.arguments, in: store)
      } catch {
        backgroundFailure = OperationFailure(
          message: String(localized: "Correction fixture could not be loaded.")
        )
      }
    #endif
  }
}
