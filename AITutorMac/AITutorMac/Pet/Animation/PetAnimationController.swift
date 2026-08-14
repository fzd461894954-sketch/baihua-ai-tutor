import AppKit
import QuartzCore

@MainActor
final class PetAnimationController {
  private enum AnimationKey {
    static let state = "PetAnimationController.state"
    static let hover = "PetAnimationController.hover"
  }

  private weak var layer: CALayer?
  private var currentState: PetState = .idle
  private var stateCompletion: ((PetState) -> Void)?
  private var completionTask: Task<Void, Never>?
  private var isHovered = false
  private var isDragging = false
  private let reduceMotionProvider: () -> Bool

  init(reduceMotionProvider: (() -> Bool)? = nil) {
    self.reduceMotionProvider = reduceMotionProvider ?? {
      NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
  }

  func attach(to layer: CALayer?) {
    guard self.layer !== layer else {
      return
    }

    stopAndReset()
    self.layer = layer
    resetModelLayer()
  }

  func play(_ state: PetState, completion: @escaping (PetState) -> Void) {
    currentState = state
    stateCompletion = completion

    guard !isInteractionPaused else {
      return
    }

    installAnimation(for: state)
  }

  func stopAndReset() {
    completionTask?.cancel()
    completionTask = nil
    stateCompletion = nil
    layer?.removeAllAnimations()
    resetModelLayer()
  }

  func refreshForAccessibilityDisplayOptions() {
    stopVisualAnimationsPreservingState()

    guard !isInteractionPaused else {
      return
    }

    installAnimation(for: currentState)
  }

  func setHovered(_ hovered: Bool) {
    guard hovered != isHovered else {
      return
    }

    isHovered = hovered
    stopVisualAnimationsPreservingState()

    if hovered {
      animateModelTransform(to: CATransform3DMakeScale(1.02, 1.02, 1))
    } else if !isInteractionPaused {
      installAnimation(for: currentState)
    }
  }

  func setDragging(_ dragging: Bool) {
    guard dragging != isDragging else {
      return
    }

    isDragging = dragging
    stopVisualAnimationsPreservingState()

    if !isInteractionPaused {
      installAnimation(for: currentState)
    }
  }

  var debugActiveAnimationCount: Int {
    layer?.animationKeys()?.count ?? 0
  }

  var debugModelTransform: CATransform3D {
    layer?.transform ?? CATransform3DIdentity
  }

  var debugModelOpacity: Float {
    layer?.opacity ?? 1
  }

  private var isInteractionPaused: Bool {
    isHovered || isDragging
  }

  private var reduceMotion: Bool {
    reduceMotionProvider()
  }

  private func installAnimation(for state: PetState) {
    layer?.removeAllAnimations()
    resetModelLayer()

    if reduceMotion {
      installReducedMotionAnimation(for: state)
      return
    }

    switch state {
    case .idle:
      addRepeatingGroup(
        animations: [
          keyframe("transform.scale", values: [1, 1.015, 1], keyTimes: [0, 0.5, 1]),
          keyframe(
            "transform.translation.y",
            values: [0, 1.5, -0.5, 0],
            keyTimes: [0, 0.45, 0.8, 1]
          ),
        ],
        duration: 3.2
      )

    case .watching:
      addRepeatingGroup(
        animations: [
          keyframe(
            "transform.rotation.z",
            values: [0, degrees(1.5), 0],
            keyTimes: [0, 0.5, 1]
          ),
          keyframe("transform.translation.x", values: [0, 1.5, 0], keyTimes: [0, 0.5, 1]),
        ],
        duration: 3.6
      )

    case .thinking:
      addRepeatingGroup(
        animations: [
          keyframe(
            "transform.rotation.z",
            values: [0, degrees(-2), degrees(2), 0],
            keyTimes: [0, 0.3, 0.7, 1]
          )
        ],
        duration: 2
      )

    case .speaking:
      addRepeatingGroup(
        animations: [
          keyframe("transform.scale", values: [1, 1.01, 1], keyTimes: [0, 0.5, 1])
        ],
        duration: 1.35
      )

    case .needsInput:
      addOneShotGroup(
        animations: [
          keyframe(
            "transform.translation.y",
            values: [0, 7, -1, 0],
            keyTimes: [0, 0.38, 0.68, 1]
          )
        ],
        duration: 0.65
      )

    case .warning:
      addOneShotGroup(
        animations: [
          keyframe(
            "transform.translation.x",
            values: [0, -3, 3, -2, 2, 0],
            keyTimes: [0, 0.18, 0.36, 0.56, 0.76, 1]
          )
        ],
        duration: 0.36
      )

    case .success:
      addOneShotGroup(
        animations: [
          keyframe(
            "transform.translation.y",
            values: [0, 8, -1, 0],
            keyTimes: [0, 0.36, 0.72, 1]
          ),
          keyframe("transform.scale", values: [1, 1.04, 1], keyTimes: [0, 0.46, 1]),
        ],
        duration: 0.85
      )
      scheduleTransientCompletion(for: state, after: 1.8)

    case .error:
      setModelTransform(CATransform3DMakeTranslation(0, -3, 0))
      addOneShotGroup(
        animations: [
          keyframe(
            "transform.translation.y",
            values: [0, -3, -3],
            keyTimes: [0, 0.5, 1]
          ),
          keyframe(
            "transform.rotation.z",
            values: [0, degrees(-1.4), degrees(1.4), 0],
            keyTimes: [0, 0.3, 0.68, 1]
          ),
        ],
        duration: 0.65
      )
    }
  }

  private func installReducedMotionAnimation(for state: PetState) {
    switch state {
    case .idle, .watching, .thinking, .speaking:
      break
    case .needsInput, .warning, .error:
      addOpacityPulse(duration: 0.45)
    case .success:
      addOpacityPulse(duration: 0.5)
      scheduleTransientCompletion(for: state, after: 0.75)
    }
  }

  private func addOpacityPulse(duration: CFTimeInterval) {
    let pulse = keyframe("opacity", values: [1, 0.78, 1], keyTimes: [0, 0.5, 1])
    addOneShotGroup(animations: [pulse], duration: duration)
  }

  private func addRepeatingGroup(
    animations: [CAAnimation],
    duration: CFTimeInterval
  ) {
    let group = animationGroup(animations: animations, duration: duration)
    group.repeatCount = .infinity
    layer?.add(group, forKey: AnimationKey.state)
  }

  private func addOneShotGroup(
    animations: [CAAnimation],
    duration: CFTimeInterval
  ) {
    let group = animationGroup(animations: animations, duration: duration)
    layer?.add(group, forKey: AnimationKey.state)
  }

  private func animationGroup(
    animations: [CAAnimation],
    duration: CFTimeInterval
  ) -> CAAnimationGroup {
    let group = CAAnimationGroup()
    group.animations = animations
    group.duration = duration
    group.isRemovedOnCompletion = true
    return group
  }

  private func keyframe(
    _ keyPath: String,
    values: [NSNumber],
    keyTimes: [NSNumber]
  ) -> CAKeyframeAnimation {
    let animation = CAKeyframeAnimation(keyPath: keyPath)
    animation.values = values
    animation.keyTimes = keyTimes
    animation.timingFunctions = Array(
      repeating: CAMediaTimingFunction(name: .easeInEaseOut),
      count: max(0, values.count - 1)
    )
    return animation
  }

  private func scheduleTransientCompletion(for state: PetState, after duration: TimeInterval) {
    completionTask?.cancel()
    completionTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
      } catch {
        return
      }

      guard let self, currentState == state, !isInteractionPaused else {
        return
      }

      stateCompletion?(state)
    }
  }

  private func stopVisualAnimationsPreservingState() {
    completionTask?.cancel()
    completionTask = nil
    layer?.removeAllAnimations()
    resetModelLayer()
  }

  private func animateModelTransform(to transform: CATransform3D) {
    guard let layer else {
      return
    }

    let currentTransform = layer.presentation()?.transform ?? layer.transform
    setModelTransform(transform)

    let animation = CABasicAnimation(keyPath: "transform")
    animation.fromValue = NSValue(caTransform3D: currentTransform)
    animation.toValue = NSValue(caTransform3D: transform)
    animation.duration = reduceMotion ? 0.08 : 0.18
    animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
    layer.add(animation, forKey: AnimationKey.hover)
  }

  private func resetModelLayer() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.transform = CATransform3DIdentity
    layer?.opacity = 1
    CATransaction.commit()
  }

  private func setModelTransform(_ transform: CATransform3D) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.transform = transform
    CATransaction.commit()
  }

  private func degrees(_ degrees: Double) -> NSNumber {
    NSNumber(value: degrees * .pi / 180)
  }
}
