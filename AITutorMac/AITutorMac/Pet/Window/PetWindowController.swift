import AppKit
import SwiftUI

@MainActor
final class PetWindowController: NSObject, NSWindowDelegate {
  private enum BubbleLayout {
    static let size = NSSize(width: 250, height: 76)
    static let gap: CGFloat = 8
  }

  private let appState: AppState
  private var pet: PetModel
  private var petImage: NSImage?
  private let configuration: PetConfiguration
  private let store: PetStore
  private let stateController: PetStateController
  private let animationController: PetAnimationController
  private let onOpenTutor: () -> Void
  private let onScaleChange: (String, Double) -> Void

  private var panel: NSPanel?
  private var bubblePanel: NSPanel?
  private var bubbleDismissTask: Task<Void, Never>?
  private var hiddenTransientTask: Task<Void, Never>?
  private var scale: CGFloat
  private var installsObservers = false

  init(
    appState: AppState,
    pet: PetModel = .officialFlowerBunny,
    petImage: NSImage? = nil,
    configuration: PetConfiguration = .default,
    store: PetStore = PetStore(),
    stateController: PetStateController,
    animationController: PetAnimationController? = nil,
    onScaleChange: @escaping (String, Double) -> Void = { _, _ in },
    onOpenTutor: @escaping () -> Void
  ) {
    self.appState = appState
    self.pet = pet
    self.petImage = petImage
    self.configuration = configuration
    self.store = store
    self.stateController = stateController
    self.animationController = animationController ?? PetAnimationController()
    self.onScaleChange = onScaleChange
    self.onOpenTutor = onOpenTutor
    scale = configuration.clampedScale(
      store.loadScale(default: configuration.defaultScale)
    )
    super.init()
    stateController.renderer = self
  }

  func start() {
    create()
    installObserversIfNeeded()

    if store.loadVisibility() {
      show()
    } else {
      appState.isPetVisible = false
    }
  }

  func create() {
    guard panel == nil else {
      return
    }

    let size = configuration.size(for: scale)
    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    panel.title = pet.name
    panel.isReleasedWhenClosed = false
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.isMovable = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.animationBehavior = .none
    panel.ignoresMouseEvents = false
    panel.acceptsMouseMovedEvents = true
    panel.delegate = self

    panel.contentView = makeInteractionView()

    let visibleFrames = NSScreen.screens.map(\.visibleFrame)
    let fallbackFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
    let origin = configuration.restoredOrigin(
      savedPosition: store.loadPosition(),
      size: size,
      visibleFrames: visibleFrames,
      fallbackVisibleFrame: fallbackFrame
    )
    panel.setFrameOrigin(origin)

    self.panel = panel
  }

  func reloadPet(_ newPet: PetModel, image: NSImage?) {
    create()
    hideWelcomeBubble()
    animationController.stopAndReset()

    pet = newPet
    petImage = image
    setScale(CGFloat(newPet.scale))

    guard let panel else {
      return
    }
    panel.title = newPet.name
    panel.contentView = makeInteractionView()

    if panel.isVisible, appState.isPetVisible {
      stateController.start()
    }

    AppLogger.pet.info("Pet window content reloaded: \(newPet.id, privacy: .public)")
  }

  func show() {
    create()
    guard let panel else {
      return
    }

    store.saveVisibility(true)
    appState.isPetVisible = true

    if !panel.isVisible {
      panel.orderFrontRegardless()
      AppLogger.pet.info("Pet shown")
    }

    stateController.start()
  }

  func hide() {
    store.saveVisibility(false)
    hideWelcomeBubble()
    animationController.stopAndReset()
    panel?.orderOut(nil)
    appState.isPetVisible = false
    AppLogger.pet.info("Pet hidden")
  }

  func stop() {
    bubbleDismissTask?.cancel()
    bubbleDismissTask = nil
    hiddenTransientTask?.cancel()
    hiddenTransientTask = nil
    bubblePanel?.orderOut(nil)
    panel?.orderOut(nil)
    animationController.stopAndReset()
    appState.isPetVisible = false

    if installsObservers {
      NotificationCenter.default.removeObserver(
        self,
        name: NSApplication.didChangeScreenParametersNotification,
        object: nil
      )
      NSWorkspace.shared.notificationCenter.removeObserver(
        self,
        name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
        object: nil
      )
      installsObservers = false
    }
  }

  @objc private func openTutor() {
    hideWelcomeBubble()
    onOpenTutor()
  }

  @objc private func increaseScale() {
    setScale(scale + configuration.scaleStep)
  }

  @objc private func decreaseScale() {
    setScale(scale - configuration.scaleStep)
  }

  @objc private func resetScale() {
    setScale(configuration.defaultScale)
  }

  @objc private func hideFromContextMenu() {
    hide()
  }

  private func setScale(_ requestedScale: CGFloat) {
    create()
    guard let panel else {
      return
    }

    let newScale = configuration.clampedScale(requestedScale)
    guard abs(newScale - scale) > 0.0001 else {
      return
    }

    let oldFrame = panel.frame
    let newSize = configuration.size(for: newScale)
    var newOrigin = NSPoint(
      x: oldFrame.midX - newSize.width / 2,
      y: oldFrame.midY - newSize.height / 2
    )

    if let visibleFrame = bestVisibleFrame(for: oldFrame) {
      newOrigin = configuration.clampedOrigin(
        newOrigin,
        size: newSize,
        in: visibleFrame
      )
    }

    scale = newScale
    panel.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: false)
    store.saveScale(newScale)
    onScaleChange(pet.id, Double(newScale))
    savePosition(newOrigin)
    positionBubbleIfNeeded()
    AppLogger.pet.info("Pet scale changed to \(Double(newScale), privacy: .public)")
  }

  private func savePosition(_ origin: NSPoint) {
    store.savePosition(PetWindowPosition(point: origin))
    AppLogger.pet.debug(
      "Pet position saved: x=\(Double(origin.x), privacy: .public), y=\(Double(origin.y), privacy: .public)"
    )
  }

  private func handleSingleClick() {
    switch stateController.currentState {
    case .idle:
      showBubble(.welcome)
    case .watching, .thinking:
      showBubble(.understanding)
    case .speaking:
      showBubble(.speaking)
    case .needsInput, .warning, .error:
      openTutor()
    case .success:
      showBubble(.success)
    }
  }

  private func showBubble(_ content: PetBubble) {
    guard appState.isPetVisible, let panel, panel.isVisible else {
      return
    }

    let bubble = bubblePanel ?? makeBubblePanel(content: content)
    bubblePanel = bubble
    bubble.contentViewController = NSHostingController(rootView: PetBubbleView(bubble: content))
    positionBubbleIfNeeded()
    bubble.orderFrontRegardless()
    AppLogger.pet.debug("Pet bubble shown")

    bubbleDismissTask?.cancel()
    let duration = configuration.bubbleDuration
    bubbleDismissTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
      } catch {
        return
      }
      self?.hideWelcomeBubble()
    }
  }

  private func hideWelcomeBubble() {
    bubbleDismissTask?.cancel()
    bubbleDismissTask = nil
    bubblePanel?.orderOut(nil)
  }

  private func makeBubblePanel(content: PetBubble) -> NSPanel {
    let bubble = NSPanel(
      contentRect: NSRect(origin: .zero, size: BubbleLayout.size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    bubble.isReleasedWhenClosed = false
    bubble.isFloatingPanel = true
    bubble.level = .floating
    bubble.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    bubble.hidesOnDeactivate = false
    bubble.isOpaque = false
    bubble.backgroundColor = .clear
    bubble.hasShadow = true
    bubble.ignoresMouseEvents = true
    bubble.animationBehavior = .utilityWindow
    bubble.contentViewController = NSHostingController(rootView: PetBubbleView(bubble: content))
    return bubble
  }

  private func positionBubbleIfNeeded() {
    guard let panel, let bubblePanel else {
      return
    }

    let petFrame = panel.frame
    let bubbleSize = bubblePanel.frame.size
    guard let visibleFrame = bestVisibleFrame(for: petFrame) else {
      return
    }

    var origin = NSPoint(
      x: petFrame.midX - bubbleSize.width / 2,
      y: petFrame.maxY + BubbleLayout.gap
    )

    if origin.y + bubbleSize.height > visibleFrame.maxY {
      origin.y = petFrame.minY - bubbleSize.height - BubbleLayout.gap
    }

    origin = configuration.clampedOrigin(origin, size: bubbleSize, in: visibleFrame)
    bubblePanel.setFrameOrigin(origin)
  }

  private func bestVisibleFrame(for windowFrame: NSRect) -> NSRect? {
    let bestScreen = NSScreen.screens.max { lhs, rhs in
      lhs.visibleFrame.intersection(windowFrame).area
        < rhs.visibleFrame.intersection(windowFrame).area
    }
    return (bestScreen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
  }

  private func makeInteractionView() -> PetInteractionView<PetView> {
    let interactionView = PetInteractionView(
      rootView: PetView(
        pet: pet,
        petImage: petImage,
        stateController: stateController
      )
    )
    animationController.attach(to: interactionView.animatedLayer)
    interactionView.onSingleClick = { [weak self] in
      self?.handleSingleClick()
    }
    interactionView.onDoubleClick = { [weak self] in
      self?.openTutor()
    }
    interactionView.onDragBegan = { [weak self] in
      AppLogger.pet.debug("Pet drag began")
      self?.hideWelcomeBubble()
      self?.animationController.setDragging(true)
    }
    interactionView.onDragEnded = { [weak self] origin in
      self?.savePosition(origin)
      self?.animationController.setDragging(false)
    }
    interactionView.onHoverChange = { [weak self] hovered in
      self?.animationController.setHovered(hovered)
    }
    interactionView.menu = makeContextMenu()
    return interactionView
  }

  private func makeContextMenu() -> NSMenu {
    let menu = NSMenu(title: pet.name)
    menu.autoenablesItems = false
    menu.addItem(menuItem("打开教学窗口", action: #selector(openTutor)))
    menu.addItem(.separator())
    menu.addItem(menuItem("放大", action: #selector(increaseScale)))
    menu.addItem(menuItem("缩小", action: #selector(decreaseScale)))
    menu.addItem(menuItem("恢复默认大小", action: #selector(resetScale)))
    menu.addItem(.separator())
    menu.addItem(menuItem("隐藏吉祥物", action: #selector(hideFromContextMenu)))
    return menu
  }

  private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.isEnabled = true
    return item
  }

  private func installObserversIfNeeded() {
    guard !installsObservers else {
      return
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenParametersDidChange),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(accessibilityDisplayOptionsDidChange),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil
    )
    installsObservers = true
  }

  @objc private func screenParametersDidChange() {
    guard let panel else {
      return
    }

    let visibleFrames = NSScreen.screens.map(\.visibleFrame)
    let restoredOrigin = configuration.restoredOrigin(
      savedPosition: PetWindowPosition(point: panel.frame.origin),
      size: panel.frame.size,
      visibleFrames: visibleFrames,
      fallbackVisibleFrame: (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
    )

    if restoredOrigin != panel.frame.origin {
      panel.setFrameOrigin(restoredOrigin)
      savePosition(restoredOrigin)
    }

    positionBubbleIfNeeded()
  }

  @objc private func accessibilityDisplayOptionsDidChange() {
    animationController.refreshForAccessibilityDisplayOptions()
  }
}

extension PetWindowController: PetStateRendering {
  func prepareForStateTransition(from state: PetState) {
    hiddenTransientTask?.cancel()
    hiddenTransientTask = nil
    hideWelcomeBubble()
    animationController.stopAndReset()
  }

  func renderPetState(_ state: PetState, completion: @escaping (PetState) -> Void) {
    guard appState.isPetVisible, panel?.isVisible == true else {
      if state.isTransient {
        hiddenTransientTask?.cancel()
        hiddenTransientTask = Task { [weak self] in
          do {
            try await Task.sleep(nanoseconds: 1_800_000_000)
          } catch {
            return
          }
          guard self != nil else {
            return
          }
          completion(state)
        }
      }
      return
    }

    animationController.play(state, completion: completion)

    if let bubble = PetBubble.automatic(for: state) {
      showBubble(bubble)
    }
  }
}

private final class PetInteractionView<Content: View>: NSView {
  var onSingleClick: (() -> Void)?
  var onDoubleClick: (() -> Void)?
  var onDragBegan: (() -> Void)?
  var onDragEnded: ((NSPoint) -> Void)?
  var onHoverChange: ((Bool) -> Void)?

  private let hostingView: NSHostingView<Content>
  private var initialMouseLocation: NSPoint?
  private var initialWindowOrigin: NSPoint?
  private var didDrag = false
  private var singleClickWorkItem: DispatchWorkItem?
  private var hoverTrackingArea: NSTrackingArea?

  var animatedLayer: CALayer? {
    hostingView.layer
  }

  init(rootView: Content) {
    hostingView = NSHostingView(rootView: rootView)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor

    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = NSColor.clear.cgColor
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(hostingView)
    NSLayoutConstraint.activate([
      hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
      hostingView.topAnchor.constraint(equalTo: topAnchor),
      hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(point) ? self : nil
  }

  override func updateTrackingAreas() {
    if let hoverTrackingArea {
      removeTrackingArea(hoverTrackingArea)
    }

    let trackingArea = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)
    hoverTrackingArea = trackingArea
    super.updateTrackingAreas()
  }

  override func mouseEntered(with event: NSEvent) {
    onHoverChange?(true)
  }

  override func mouseExited(with event: NSEvent) {
    onHoverChange?(false)
  }

  override func mouseDown(with event: NSEvent) {
    initialMouseLocation = NSEvent.mouseLocation
    initialWindowOrigin = window?.frame.origin
    didDrag = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard
      let window,
      let initialMouseLocation,
      let initialWindowOrigin
    else {
      return
    }

    let currentMouseLocation = NSEvent.mouseLocation
    let deltaX = currentMouseLocation.x - initialMouseLocation.x
    let deltaY = currentMouseLocation.y - initialMouseLocation.y

    if !didDrag, hypot(deltaX, deltaY) >= 3 {
      didDrag = true
      singleClickWorkItem?.cancel()
      onDragBegan?()
    }

    guard didDrag else {
      return
    }

    window.setFrameOrigin(
      NSPoint(
        x: initialWindowOrigin.x + deltaX,
        y: initialWindowOrigin.y + deltaY
      )
    )
  }

  override func mouseUp(with event: NSEvent) {
    defer {
      initialMouseLocation = nil
      initialWindowOrigin = nil
      didDrag = false
    }

    if didDrag {
      if let origin = window?.frame.origin {
        onDragEnded?(origin)
      }
      return
    }

    if event.clickCount >= 2 {
      singleClickWorkItem?.cancel()
      singleClickWorkItem = nil
      onDoubleClick?()
      return
    }

    let workItem = DispatchWorkItem { [weak self] in
      self?.onSingleClick?()
      self?.singleClickWorkItem = nil
    }
    singleClickWorkItem?.cancel()
    singleClickWorkItem = workItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + NSEvent.doubleClickInterval,
      execute: workItem
    )
  }

  override func rightMouseDown(with event: NSEvent) {
    guard let menu else {
      return
    }

    NSMenu.popUpContextMenu(menu, with: event, for: self)
  }
}

private extension NSRect {
  var area: CGFloat {
    isNull ? 0 : width * height
  }
}
