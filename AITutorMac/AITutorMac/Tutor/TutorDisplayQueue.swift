import Foundation
import Observation

struct TutorDisplayQueueConfiguration: Equatable, Sendable {
  static let `default` = TutorDisplayQueueConfiguration(maximumQueuedItemCount: 8)

  let maximumQueuedItemCount: Int

  init(maximumQueuedItemCount: Int) {
    self.maximumQueuedItemCount = max(1, maximumQueuedItemCount)
  }
}

struct TutorDisplayItem: Equatable, Sendable, Identifiable {
  var id: UUID {
    presentation.responseMetadata.responseID
  }

  var sourceChunkID: UUID {
    presentation.responseMetadata.sourceChunkID
  }

  let presentation: TutorPresentationModel
  let policyInput: TutorInteractionInput
  let decision: TutorInteractionDecision
}

/// Local presentation scheduler. Waiting items are ordered by priority and,
/// within a priority, newest response first.
@MainActor
@Observable
final class TutorDisplayQueue {
  private(set) var currentDisplayItem: TutorDisplayItem?
  private(set) var queuedItems: [TutorDisplayItem] = []
  private(set) var duplicateMergeCount = 0
  private(set) var lastCancelledItemID: UUID?

  var queueCount: Int {
    queuedItems.count
  }

  @ObservationIgnored private let configuration: TutorDisplayQueueConfiguration

  init(configuration: TutorDisplayQueueConfiguration = .default) {
    self.configuration = configuration
  }

  func submit(
    _ presentation: TutorPresentationModel,
    input: TutorInteractionInput,
    decision: TutorInteractionDecision
  ) {
    let item = TutorDisplayItem(
      presentation: presentation,
      policyInput: input,
      decision: decision
    )

    switch decision.action {
    case .show:
      show(item)
    case .queue:
      enqueue(item)
    case .ignore:
      return
    }
  }

  func displayNextQueuedItem() {
    guard !queuedItems.isEmpty else {
      currentDisplayItem = nil
      return
    }
    if let currentDisplayItem {
      lastCancelledItemID = currentDisplayItem.id
    }
    currentDisplayItem = queuedItems.removeFirst()
  }

  func cancelCurrentDisplay() {
    lastCancelledItemID = currentDisplayItem?.id
    currentDisplayItem = nil
  }

  func reset() {
    currentDisplayItem = nil
    queuedItems.removeAll(keepingCapacity: false)
    duplicateMergeCount = 0
    lastCancelledItemID = nil
  }

  private func show(_ item: TutorDisplayItem) {
    removeQueuedDuplicate(of: item)

    if let currentDisplayItem {
      if currentDisplayItem.sourceChunkID == item.sourceChunkID {
        duplicateMergeCount += 1
      }
      guard isNewer(item, than: currentDisplayItem) else {
        return
      }
      lastCancelledItemID = currentDisplayItem.id
    }
    currentDisplayItem = item
  }

  private func enqueue(_ item: TutorDisplayItem) {
    if let currentDisplayItem,
       currentDisplayItem.sourceChunkID == item.sourceChunkID {
      duplicateMergeCount += 1
      if isNewer(item, than: currentDisplayItem) {
        lastCancelledItemID = currentDisplayItem.id
        self.currentDisplayItem = item
      }
      return
    }

    if let duplicateIndex = queuedItems.firstIndex(
      where: { $0.sourceChunkID == item.sourceChunkID }
    ) {
      duplicateMergeCount += 1
      if isNewer(item, than: queuedItems[duplicateIndex]) {
        queuedItems[duplicateIndex] = item
      }
    } else {
      queuedItems.append(item)
    }

    sortAndTrimQueue()
  }

  private func removeQueuedDuplicate(of item: TutorDisplayItem) {
    let originalCount = queuedItems.count
    queuedItems.removeAll { $0.sourceChunkID == item.sourceChunkID }
    if queuedItems.count != originalCount {
      duplicateMergeCount += 1
    }
  }

  private func sortAndTrimQueue() {
    queuedItems.sort { lhs, rhs in
      if lhs.decision.priority != rhs.decision.priority {
        return lhs.decision.priority.rawValue > rhs.decision.priority.rawValue
      }
      return isNewer(lhs, than: rhs)
    }
    if queuedItems.count > configuration.maximumQueuedItemCount {
      queuedItems.removeLast(queuedItems.count - configuration.maximumQueuedItemCount)
    }
  }

  private func isNewer(_ lhs: TutorDisplayItem, than rhs: TutorDisplayItem) -> Bool {
    let lhsMetadata = lhs.presentation.responseMetadata
    let rhsMetadata = rhs.presentation.responseMetadata
    if lhsMetadata.sessionID == rhsMetadata.sessionID,
       lhsMetadata.sequence != rhsMetadata.sequence {
      return lhsMetadata.sequence > rhsMetadata.sequence
    }
    if lhsMetadata.createdAt != rhsMetadata.createdAt {
      return lhsMetadata.createdAt > rhsMetadata.createdAt
    }
    return lhsMetadata.responseID.uuidString > rhsMetadata.responseID.uuidString
  }
}
