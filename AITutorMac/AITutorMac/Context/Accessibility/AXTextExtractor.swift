import Foundation

struct AXTextExtractionResult {
  let nodes: [AccessibleTextNode]
  let plainText: String
  let visitedNodeCount: Int
  let roleCounts: [String: Int]
  let truncated: Bool
}

struct AXTextExtractor {
  let limits: AccessibilityTraversalLimits

  init(limits: AccessibilityTraversalLimits = .default) {
    self.limits = limits
  }

  func extract(
    from root: any AXElementReading,
    cancellationToken: AccessibilityReadCancellationToken,
    sourceApplication: AccessibleApplicationSnapshot? = nil,
    sourceWindow: AccessibleWindowSnapshot? = nil,
    windowFrame: CGRect? = nil
  ) throws -> AXTextExtractionResult {
    struct TraversalItem {
      let element: any AXElementReading
      let depth: Int
      let childIndex: Int
      let ancestors: [AccessibleNodePathComponent]
      let ancestorText: Set<String>
    }

    var stack: [TraversalItem] = [
      TraversalItem(
        element: root,
        depth: 0,
        childIndex: 0,
        ancestors: [],
        ancestorText: []
      )
    ]
    var nodes: [AccessibleTextNode] = []
    var visitedNodeCount = 0
    var roleCounts: [String: Int] = [:]
    var storedCharacterCount = 0
    var truncated = false

    while let item = stack.popLast() {
      try cancellationToken.checkCancellation()

      if visitedNodeCount >= limits.maxNodes {
        truncated = true
        break
      }

      let traversalIndex = visitedNodeCount
      visitedNodeCount += 1
      let role = try readString(item.element, .role)
      let subrole = try readString(item.element, .subrole)
      if let role {
        roleCounts[role, default: 0] += 1
      }

      if Self.isSecure(role: role, subrole: subrole) {
        continue
      }

      let identifier = try readString(item.element, .identifier)
      let title = try readString(item.element, .title)
      let value = try readString(item.element, .value)
      let selectedText = try readString(item.element, .selectedText)
      let elementDescription = try readString(item.element, .accessibilityDescription)
      let help = try readString(item.element, .help)
      let frame = try readFrame(item.element)
      let focused = try readBoolean(item.element, .focused)
      let selected = try readBoolean(item.element, .selected)
      let enabled = try readBoolean(item.element, .enabled)
      let visible = try readBoolean(item.element, .visible)
      let elementFingerprint = Self.fingerprint(
        parts: [
          item.ancestors.map(\.debugNodeID).joined(separator: "/"),
          role ?? "",
          subrole ?? "",
          identifier ?? "",
          String(item.childIndex),
          frame.map(Self.frameDescription) ?? "",
        ]
      )
      let debugNodeID = String(
        format: "AXN-%04d-%@",
        traversalIndex,
        String(elementFingerprint.prefix(8))
      )
      let frameSnapshot = frame.map(AccessibleFrameSnapshot.init)
      let pathComponent = AccessibleNodePathComponent(
        debugNodeID: debugNodeID,
        role: role,
        subrole: subrole,
        identifier: identifier,
        traversalIndex: traversalIndex,
        childIndex: item.childIndex,
        frame: frameSnapshot,
        isFocused: focused,
        isSelected: selected
      )
      let geometryRelationship = Self.geometryRelationship(
        frame: frame,
        windowFrame: windowFrame
      )
      let windowIdentity = sourceWindow.map(Self.windowIdentity)
      let attributes: [(String?, AccessibilityTextSourceAttribute)] = [
        (title, .title),
        (value, .value),
        (elementDescription, .accessibilityDescription),
        (help, .help),
        (selectedText, .selectedText),
      ]
      var elementText: Set<String> = []
      let nodeCountBeforeElementText = nodes.count

      for (rawText, source) in attributes {
        try cancellationToken.checkCancellation()
        guard let rawText, !rawText.isEmpty else {
          continue
        }

        let text = Self.normalize(rawText)
        guard !text.isEmpty else {
          continue
        }

        // Duplicate attributes on one AX element and exact copies exposed by
        // descendants are omitted. Equal text in sibling message containers
        // is retained because it has different provenance.
        let isSelectedText = source == .selectedText
        guard isSelectedText || !elementText.contains(text) else {
          continue
        }
        guard isSelectedText || !item.ancestorText.contains(text) else {
          continue
        }

        let separatorCost = nodes.isEmpty ? 0 : 1
        let available = limits.maxCharacters - storedCharacterCount - separatorCost
        guard available > 0 else {
          truncated = true
          break
        }

        let storedText = String(text.prefix(available))
        let rawStoredText = String(rawText.prefix(max(available, storedText.count)))
        nodes.append(
          AccessibleTextNode(
            role: role,
            text: storedText,
            depth: item.depth,
            sourceAttribute: source,
            debugNodeID: debugNodeID,
            fingerprint: Self.fingerprint(
              parts: [elementFingerprint, source.rawValue, storedText]
            ),
            subrole: subrole,
            identifier: identifier,
            elementTitle: title,
            elementDescription: elementDescription,
            rawText: rawStoredText,
            traversalIndex: traversalIndex,
            parentDebugNodeID: item.ancestors.last?.debugNodeID,
            ancestorPath: item.ancestors,
            frame: frameSnapshot,
            isFocused: focused,
            isSelected: selected,
            isEnabled: enabled,
            isVisible: visible,
            windowGeometryRelationship: geometryRelationship,
            sourceApplication: sourceApplication?.appName,
            sourceBundleIdentifier: sourceApplication?.bundleIdentifier,
            sourceProcessIdentifier: sourceApplication?.processIdentifier,
            sourceWindowIdentity: windowIdentity
          )
        )
        storedCharacterCount += separatorCost + storedText.count
        if !isSelectedText {
          elementText.insert(text)
        }

        if storedText.count < text.count {
          truncated = true
          break
        }
      }

      if truncated && storedCharacterCount >= limits.maxCharacters {
        break
      }

      let children = try readChildren(
        item.element,
        maySkipFailure: nodes.count > nodeCountBeforeElementText
          && (focused == true || selected == true || selectedText?.isEmpty == false)
      )
      if item.depth >= limits.maxDepth {
        if !children.isEmpty {
          truncated = true
        }
        continue
      }

      let descendantAncestorText = item.ancestorText.union(elementText)
      for (childIndex, child) in children.enumerated().reversed() {
        stack.append(
          TraversalItem(
            element: child,
            depth: item.depth + 1,
            childIndex: childIndex,
            ancestors: item.ancestors + [pathComponent],
            ancestorText: descendantAncestorText
          )
        )
      }
    }

    let nonSelectionNodeIDs = Set(
      nodes.lazy
        .filter { $0.sourceAttribute != .selectedText }
        .map(\.debugNodeID)
    )
    let plainTextNodes = nodes.filter {
      $0.sourceAttribute != .selectedText || !nonSelectionNodeIDs.contains($0.debugNodeID)
    }
    let plainText = plainTextNodes.map(\.text).joined(separator: "\n")
    return AXTextExtractionResult(
      nodes: nodes,
      plainText: plainText,
      visitedNodeCount: visitedNodeCount,
      roleCounts: roleCounts,
      truncated: truncated
    )
  }

  private func readString(
    _ element: any AXElementReading,
    _ attribute: AXReadableAttribute
  ) throws -> String? {
    do {
      return try element.stringValue(for: attribute)
    } catch {
      if attribute == .accessibilityDescription {
#if DEBUG
        AXReadTraceStore.shared.record(
          stage: .treeTraversal,
          outcome: .warning,
          operation: "skip-optional-attribute-failure",
          attribute: attribute.rawValue,
          detail: "Reliable content does not require AXDescription."
        )
#endif
        return nil
      }
      throw AccessibilityReaderError.readFailed
    }
  }

  private func readBoolean(
    _ element: any AXElementReading,
    _ attribute: AXReadableBooleanAttribute
  ) throws -> Bool? {
    do {
      return try element.booleanValue(for: attribute)
    } catch {
      throw AccessibilityReaderError.readFailed
    }
  }

  private func readFrame(_ element: any AXElementReading) throws -> CGRect? {
    do {
      return try element.elementFrame()
    } catch {
      throw AccessibilityReaderError.readFailed
    }
  }

  private func readChildren(
    _ element: any AXElementReading,
    maySkipFailure: Bool
  ) throws -> [any AXElementReading] {
    do {
      return try element.childElements()
    } catch {
      if maySkipFailure {
#if DEBUG
        AXReadTraceStore.shared.record(
          stage: .treeTraversal,
          outcome: .warning,
          operation: "skip-child-traversal-failure-after-reliable-text",
          attribute: AXReadableAttribute.children.rawValue
        )
#endif
        return []
      }
      throw AccessibilityReaderError.readFailed
    }
  }

  private static func isSecure(role: String?, subrole: String?) -> Bool {
    role == "AXSecureTextField"
      || subrole?.localizedCaseInsensitiveContains("secure") == true
      || subrole?.localizedCaseInsensitiveContains("password") == true
  }

  private static func normalize(_ text: String) -> String {
    var lines = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")
    while lines.first?.allSatisfy(\.isWhitespace) == true {
      lines.removeFirst()
    }
    while lines.last?.allSatisfy(\.isWhitespace) == true {
      lines.removeLast()
    }
    if lines.count == 1, let line = lines.first {
      return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return lines.joined(separator: "\n")
  }

  private static func geometryRelationship(
    frame: CGRect?,
    windowFrame: CGRect?
  ) -> AccessibleWindowGeometryRelationship {
    guard let frame, let windowFrame, frame.width > 0, frame.height > 0 else {
      return .unknown
    }
    if windowFrame.contains(frame) {
      return .containedInWindow
    }
    if windowFrame.intersects(frame) {
      return .intersectsWindow
    }
    return .outsideWindow
  }

  private static func frameDescription(_ frame: CGRect) -> String {
    String(
      format: "%.1f,%.1f,%.1f,%.1f",
      frame.origin.x,
      frame.origin.y,
      frame.size.width,
      frame.size.height
    )
  }

  private static func windowIdentity(_ window: AccessibleWindowSnapshot) -> String {
    [
      window.application.bundleIdentifier ?? window.application.appName ?? "unknown-app",
      String(window.application.processIdentifier),
      window.windowRole ?? "unknown-role",
      window.windowSubrole ?? "unknown-subrole",
      window.windowTitle ?? "untitled-window",
    ].joined(separator: "|")
  }

  private static func fingerprint(parts: [String]) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in parts.joined(separator: "\u{1f}").utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 1_099_511_628_211
    }
    return String(format: "%016llx", hash)
  }
}
