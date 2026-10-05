import AppKit
import QuartzCore
import XCTest

@testable import AITutorMac

@MainActor
final class PetStateTests: XCTestCase {
  func testInitialStateIsIdle() {
    let controller = PetStateController()

    XCTAssertEqual(controller.currentState, .idle)
  }

  func testTransitionStopsOldStateBeforeRenderingNewState() {
    let controller = PetStateController()
    let renderer = RecordingPetStateRenderer()
    controller.renderer = renderer

    controller.transition(to: .thinking)

    XCTAssertEqual(controller.currentState, .thinking)
    XCTAssertEqual(renderer.events, ["prepare:idle", "render:thinking"])
  }

  func testSuccessCompletionReturnsToIdle() throws {
    let controller = PetStateController()
    let renderer = RecordingPetStateRenderer()
    controller.renderer = renderer

    controller.transition(to: .success)
    try XCTUnwrap(renderer.completion)(.success)

    XCTAssertEqual(controller.currentState, .idle)
    XCTAssertEqual(
      renderer.events,
      [
        "prepare:idle",
        "render:success",
        "prepare:success",
        "render:idle",
      ]
    )
  }

  func testStaleSuccessCompletionCannotOverrideNewerState() throws {
    let controller = PetStateController()
    let renderer = RecordingPetStateRenderer()
    controller.renderer = renderer

    controller.transition(to: .success)
    let successCompletion = try XCTUnwrap(renderer.completion)
    controller.transition(to: .thinking)
    successCompletion(.success)

    XCTAssertEqual(controller.currentState, .thinking)
  }

  func testEveryStateHasStableChineseDisplayName() {
    let expected: [PetState: String] = [
      .idle: "待机",
      .watching: "正在观察",
      .thinking: "正在理解",
      .speaking: "正在解释",
      .needsInput: "等待你的操作",
      .warning: "需要注意",
      .success: "已完成",
      .error: "出现问题",
    ]

    XCTAssertEqual(PetState.allCases.count, expected.count)
    for state in PetState.allCases {
      XCTAssertEqual(state.displayName, expected[state])
    }
  }

  func testThirtyStateTransitionsDoNotAccumulateAnimationsOrTransforms() {
    let layer = CALayer()
    let animationController = PetAnimationController(reduceMotionProvider: { false })
    let renderer = AnimationPetStateRenderer(animationController: animationController)
    let stateController = PetStateController()
    animationController.attach(to: layer)
    stateController.renderer = renderer

    let sequence: [PetState] = [
      .idle,
      .thinking,
      .warning,
      .success,
      .watching,
      .speaking,
      .needsInput,
      .error,
    ]

    for index in 0..<30 {
      stateController.transition(to: sequence[index % sequence.count])
      XCTAssertLessThanOrEqual(animationController.debugActiveAnimationCount, 1)
    }

    stateController.transition(to: .idle)

    XCTAssertEqual(stateController.currentState, .idle)
    XCTAssertLessThanOrEqual(animationController.debugActiveAnimationCount, 1)
    XCTAssertTrue(CATransform3DIsIdentity(animationController.debugModelTransform))
    XCTAssertEqual(animationController.debugModelOpacity, 1, accuracy: 0.0001)
  }

  func testReduceMotionRemovesContinuousMovementAndKeepsStaticStateFeedback() {
    let layer = CALayer()
    let animationController = PetAnimationController(reduceMotionProvider: { true })
    animationController.attach(to: layer)

    animationController.play(.thinking) { _ in }
    XCTAssertEqual(animationController.debugActiveAnimationCount, 0)

    animationController.play(.warning) { _ in }
    XCTAssertEqual(animationController.debugActiveAnimationCount, 1)

    animationController.stopAndReset()
    XCTAssertEqual(animationController.debugActiveAnimationCount, 0)
    XCTAssertTrue(CATransform3DIsIdentity(animationController.debugModelTransform))
    XCTAssertEqual(animationController.debugModelOpacity, 1, accuracy: 0.0001)
  }

  func testCustomStaticPetReloadKeepsStateAndSupportsAllEightAnimations() throws {
    let suiteName = "PetStateTests.CustomReload.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let appState = AppState()
    let stateController = PetStateController()
    let animationController = PetAnimationController(reduceMotionProvider: { false })
    let voiceController = VoiceController(petStateController: stateController)
    let speechInputController = SpeechInputController(
      authorizationController: SpeechAuthorizationController(),
      recognizerFactory: SystemSpeechRecognizerFactory(),
      voiceOutputController: voiceController
    )
    let windowController = PetWindowController(
      appState: appState,
      pet: .officialFlowerBunny,
      petImage: NSImage(named: "official_flower_bunny"),
      store: PetStore(defaults: defaults),
      stateController: stateController,
      speechInputController: speechInputController,
      tutorNotificationCenter: TutorPetNotificationCenter(),
      animationController: animationController,
      onOpenTutor: {}
    )
    let customPet = PetModel(
      id: "user_\(UUID().uuidString.lowercased())",
      name: "测试角色",
      source: .userImported,
      type: .staticImage,
      assetLocation: "pet.png",
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      scale: 1
    )

    windowController.start()
    stateController.transition(to: .thinking)
    windowController.reloadPet(
      customPet,
      image: NSImage(named: "official_flower_bunny")
    )

    XCTAssertEqual(stateController.currentState, .thinking)
    for state in PetState.allCases {
      stateController.transition(to: state)
      XCTAssertEqual(stateController.currentState, state)
      XCTAssertLessThanOrEqual(animationController.debugActiveAnimationCount, 1)
    }

    windowController.stop()
  }
}

@MainActor
private final class RecordingPetStateRenderer: PetStateRendering {
  var events: [String] = []
  var completion: ((PetState) -> Void)?

  func prepareForStateTransition(from state: PetState) {
    events.append("prepare:\(state.rawValue)")
  }

  func renderPetState(_ state: PetState, completion: @escaping (PetState) -> Void) {
    events.append("render:\(state.rawValue)")
    self.completion = completion
  }
}

@MainActor
private final class AnimationPetStateRenderer: PetStateRendering {
  private let animationController: PetAnimationController

  init(animationController: PetAnimationController) {
    self.animationController = animationController
  }

  func prepareForStateTransition(from state: PetState) {
    animationController.stopAndReset()
  }

  func renderPetState(_ state: PetState, completion: @escaping (PetState) -> Void) {
    animationController.play(state, completion: completion)
  }
}
