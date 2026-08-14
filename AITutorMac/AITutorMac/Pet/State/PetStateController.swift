import Observation
import OSLog

@MainActor
protocol PetStateRendering: AnyObject {
  func prepareForStateTransition(from state: PetState)
  func renderPetState(_ state: PetState, completion: @escaping (PetState) -> Void)
}

@MainActor
@Observable
final class PetStateController {
  private(set) var currentState: PetState = .idle

  @ObservationIgnored
  weak var renderer: (any PetStateRendering)?

  func start() {
    renderer?.renderPetState(currentState, completion: transientStateDidComplete)
  }

  func transition(to newState: PetState) {
    guard newState != currentState else {
      return
    }

    let oldState = currentState
    renderer?.prepareForStateTransition(from: oldState)
    currentState = newState

    AppLogger.pet.info(
      "Pet state: \(oldState.rawValue, privacy: .public) → \(newState.rawValue, privacy: .public)"
    )

    renderer?.renderPetState(newState, completion: transientStateDidComplete)
  }

  func transientStateDidComplete(_ completedState: PetState) {
    guard completedState.isTransient, currentState == completedState else {
      return
    }

    transition(to: .idle)
  }
}
