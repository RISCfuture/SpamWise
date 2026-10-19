public import Foundation

/// Why a folder plan could not be saved.
public enum FolderPlanError: Error, LocalizedError, Sendable, Equatable {
  /// A training plan's folder is not named as its purpose requires.
  case misnamed(folder: String, required: String)
  /// A training folder already holds mail, so earlier placements cannot be told apart.
  case notEmpty(folder: String, count: Int)
  /// Saving would exceed the number of plans SpamWise keeps.
  case limitReached(limit: Int)
  /// No saved plan has this identifier.
  case notFound

  /// A general description of the failure.
  public var errorDescription: String? {
    String(localized: "Couldn’t save the folder plan.", bundle: .module)
  }
  /// The specific cause.
  public var failureReason: String? {
    switch self {
      case let .misnamed(folder, required):
        String(localized: "The folder “\(folder)” isn’t named “\(required)”.", bundle: .module)
      case .notEmpty(let folder, _):
        String(localized: "The folder “\(folder)” isn’t empty.", bundle: .module)
      case .limitReached(let limit):
        String(
          localized: "SpamWise keeps at most \(limit, format: .number) folder plans.",
          bundle: .module
        )
      case .notFound: String(localized: "The folder plan no longer exists.", bundle: .module)
    }
  }
  /// What the user can do about it.
  public var recoverySuggestion: String? {
    switch self {
      case .misnamed(_, let required):
        String(
          localized: "Create a dedicated folder named “\(required)” in Mail, then select it.",
          bundle: .module
        )
      case .notEmpty:
        String(
          localized:
            "Move its messages elsewhere so the folder is empty, then save the plan again.",
          bundle: .module
        )
      case .limitReached:
        String(localized: "Remove a plan you no longer use, then try again.", bundle: .module)
      case .notFound: nil
    }
  }
}

/// A saved folder plan with whether its folder still resolves.
public struct FolderPlanStatus: Sendable, Identifiable {
  /// The saved plan.
  public var plan: MailFolderPlan
  /// Whether the client currently lists the plan's folder; nil when folders were not listed.
  public var folderResolves: Bool?
  /// The plan's stable identifier.
  public var id: String { plan.id }
}

/// Saving, listing, disabling and removing configured folder plans.
public enum FolderPlans {
  /// Most plans SpamWise keeps; sweeps process at most this many enabled plans.
  public static let limit = 20

  /**
   Lists every saved plan, including plans whose folder no longer resolves.

   - Parameters:
     - store: The store holding the saved plans.
     - folders: The folders the client currently lists, or nil when unknown.
   */
  public static func list(in store: Store, resolving folders: [MailFolder]? = nil) async throws
    -> [FolderPlanStatus]
  {
    statuses(
      try await StateRepository.load(store, StateSlices()).settings.mailOptions.folderPlans,
      resolving: folders
    )
  }

  /// Pairs each plan with whether `folders` lists its folder; nil folders leave that unknown.
  public static func statuses(_ plans: [MailFolderPlan], resolving folders: [MailFolder]?)
    -> [FolderPlanStatus]
  {
    let ids = folders.map { Set($0.map(\.id)) }
    return plans.map { FolderPlanStatus(plan: $0, folderResolves: ids?.contains($0.id)) }
  }

  /**
   Validates and saves a plan, replacing a saved plan for the same folder.

   A training plan requires its dedicated folder name and an empty folder when first saved for
   that purpose.

   - Throws: ``FolderPlanError`` for a misnamed or non-empty training folder or a full plan list.
   */
  public static func save(_ plan: MailFolderPlan, source: any MailSweepSource, in store: Store)
    async throws
  {
    let saved = try await validated(plan, source: source, store: store)
    try await StateRepository.editSettings(store) { settings in
      var plans = settings.mailOptions.folderPlans
      plans.removeAll { $0.id == saved.id }
      guard plans.count < limit else { throw FolderPlanError.limitReached(limit: limit) }
      plans.append(saved)
      settings.mailOptions.folderPlans = plans
    }
  }

  /// Turns automatic processing of a saved plan on or off.
  public static func setEnabled(_ enabled: Bool, planID: String, in store: Store) async throws {
    try await editPlans(in: store) { plans in
      guard let index = plans.firstIndex(where: { $0.id == planID }) else {
        throw FolderPlanError.notFound
      }
      plans[index].enabled = enabled
    }
  }

  /// Removes a saved plan; its folder and the mail in it are left unchanged.
  public static func remove(planID: String, in store: Store) async throws {
    try await editPlans(in: store) { plans in
      guard plans.contains(where: { $0.id == planID }) else { throw FolderPlanError.notFound }
      plans.removeAll { $0.id == planID }
    }
  }

  private static func validated(
    _ plan: MailFolderPlan,
    source: any MailSweepSource,
    store: Store
  ) async throws -> MailFolderPlan {
    guard let required = TrainingFolders.name(for: plan.purpose) else { return plan }
    guard plan.folder.path.last == required else {
      throw FolderPlanError.misnamed(folder: plan.folder.displayName, required: required)
    }
    var validated = plan
    let current = try await StateRepository.load(store, StateSlices()).settings.mailOptions
      .folderPlans.first { $0.id == plan.id }
    if current?.trainingBaselineValidated != true || current?.purpose != plan.purpose {
      let page = try await source.folderPage(plan.folder, offset: 0, limit: 1, since: nil)
      guard page.total == 0 else {
        throw FolderPlanError.notEmpty(folder: plan.folder.displayName, count: page.total)
      }
    }
    validated.trainingBaselineValidated = true
    return validated
  }

  private static func editPlans(
    in store: Store,
    _ edit: @Sendable (inout [MailFolderPlan]) throws -> Void
  ) async throws {
    try await StateRepository.editSettings(store) { settings in
      var plans = settings.mailOptions.folderPlans
      try edit(&plans)
      settings.mailOptions.folderPlans = plans
    }
  }
}
