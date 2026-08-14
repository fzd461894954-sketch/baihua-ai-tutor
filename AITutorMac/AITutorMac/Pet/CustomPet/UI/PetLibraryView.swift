import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct PetLibraryView: View {
  let library: PetLibrary
  let importer: PetImporter

  @State private var preparedImport: PreparedPetImport?
  @State private var deleteCandidate: PetModel?
  @State private var errorMessage = ""
  @State private var isShowingError = false
  @State private var isPreparingPreview = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text("我的桌面老师")
          .font(.title2.weight(.semibold))
        Text("选择一个角色作为桌面老师，或导入你自己的透明 PNG。")
          .foregroundStyle(.secondary)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          roleSection(
            title: "官方",
            pets: library.pets.filter { $0.source == .bundled }
          )
          roleSection(
            title: "我的角色",
            pets: library.pets.filter { $0.source == .userImported }
          )
        }
        .padding(.vertical, 2)
      }

      Divider()

      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("你的角色图片只保存在这台 Mac 上。")
            .font(.callout)
          Text("软件不会修改或删除你选择的原始 PNG。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        if isPreparingPreview {
          ProgressView()
            .controlSize(.small)
        }

        Button {
          Task { await choosePNG() }
        } label: {
          Label("添加我的角色", systemImage: "plus")
        }
        .keyboardShortcut("n", modifiers: .command)
        .disabled(isPreparingPreview)
      }
    }
    .padding(22)
    .frame(minWidth: 560, minHeight: 500)
    .sheet(item: $preparedImport) { prepared in
      PetImportPreviewView(
        prepared: prepared,
        importer: importer,
        library: library,
        onCancel: { preparedImport = nil },
        onReselect: {
          preparedImport = nil
          Task { await choosePNG() }
        },
        onImported: { preparedImport = nil }
      )
    }
    .alert(
      "是否从“白话 AI”中删除这个角色？",
      isPresented: deleteConfirmationPresented,
      presenting: deleteCandidate
    ) { pet in
      Button("删除角色", role: .destructive) {
        delete(pet)
      }
      Button("取消", role: .cancel) {}
    } message: { _ in
      Text("只会删除软件保存在本机的副本，不会删除你原来的 PNG 文件。")
    }
    .alert("操作未完成", isPresented: $isShowingError) {
      Button("好", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  @ViewBuilder
  private func roleSection(title: String, pets: [PetModel]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)

      if pets.isEmpty {
        Text("还没有导入角色。")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(14)
          .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
      } else {
        ForEach(pets) { pet in
          PetLibraryRow(
            pet: pet,
            thumbnail: library.thumbnail(for: pet),
            isCurrent: library.currentPet.id == pet.id,
            onSelect: { select(pet) },
            onDelete: pet.source == .userImported
              ? { deleteCandidate = pet }
              : nil
          )
        }
      }
    }
  }

  private var deleteConfirmationPresented: Binding<Bool> {
    Binding(
      get: { deleteCandidate != nil },
      set: { isPresented in
        if !isPresented {
          deleteCandidate = nil
        }
      }
    )
  }

  private func choosePNG() async {
    let panel = NSOpenPanel()
    panel.title = "选择你的桌面老师"
    panel.prompt = "预览"
    panel.message = "请选择一张 PNG。推荐使用带透明背景的图片。"
    panel.allowedContentTypes = [.png]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true

    guard await panel.begin() == .OK, let sourceURL = panel.url else {
      return
    }

    isPreparingPreview = true
    let result = await Task.detached(priority: .userInitiated) {
      Result { try importer.prepare(sourceURL) }
    }.value
    isPreparingPreview = false

    switch result {
    case let .success(prepared):
      preparedImport = prepared
    case let .failure(error):
      present(error)
    }
  }

  private func select(_ pet: PetModel) {
    do {
      try library.select(pet.id)
    } catch {
      present(error)
    }
  }

  private func delete(_ pet: PetModel) {
    do {
      try library.delete(pet)
    } catch {
      present(error)
    }
  }

  private func present(_ error: Error) {
    errorMessage = (error as? LocalizedError)?.errorDescription
      ?? "操作没有完成，请稍后再试。"
    isShowingError = true
  }
}

private struct PetLibraryRow: View {
  let pet: PetModel
  let thumbnail: NSImage?
  let isCurrent: Bool
  let onSelect: () -> Void
  let onDelete: (() -> Void)?

  var body: some View {
    HStack(spacing: 14) {
      Group {
        if let thumbnail {
          Image(nsImage: thumbnail)
            .resizable()
            .scaledToFit()
        } else {
          Image(systemName: "photo.badge.exclamationmark")
            .font(.title)
            .foregroundStyle(.secondary)
        }
      }
      .frame(width: 62, height: 62)
      .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))

      VStack(alignment: .leading, spacing: 4) {
        Text(pet.name)
          .font(.body.weight(.medium))
        Text(pet.source == .bundled ? "官方角色" : "我的角色")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if isCurrent {
        Label("正在使用", systemImage: "checkmark.circle.fill")
          .font(.callout)
          .foregroundStyle(.green)
      } else {
        Button("使用", action: onSelect)
      }

      if let onDelete {
        Button(role: .destructive, action: onDelete) {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .help("删除这个角色")
      }
    }
    .padding(10)
    .background(.background, in: RoundedRectangle(cornerRadius: 11))
    .overlay {
      RoundedRectangle(cornerRadius: 11)
        .stroke(isCurrent ? Color.accentColor.opacity(0.55) : .secondary.opacity(0.16))
    }
  }
}

private struct PetImportPreviewView: View {
  enum PreviewBackground: String, CaseIterable, Identifiable {
    case light = "浅色"
    case dark = "深色"

    var id: String { rawValue }
  }

  let prepared: PreparedPetImport
  let importer: PetImporter
  let library: PetLibrary
  let onCancel: () -> Void
  let onReselect: () -> Void
  let onImported: () -> Void

  @State private var name: String
  @State private var scale = PetConfiguration.default.defaultScale
  @State private var previewBackground = PreviewBackground.light
  @State private var isSaving = false
  @State private var errorMessage = ""
  @State private var isShowingError = false

  init(
    prepared: PreparedPetImport,
    importer: PetImporter,
    library: PetLibrary,
    onCancel: @escaping () -> Void,
    onReselect: @escaping () -> Void,
    onImported: @escaping () -> Void
  ) {
    self.prepared = prepared
    self.importer = importer
    self.library = library
    self.onCancel = onCancel
    self.onReselect = onReselect
    self.onImported = onImported
    _name = State(initialValue: prepared.suggestedName)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("角色预览")
        .font(.title2.weight(.semibold))

      Picker("预览背景", selection: $previewBackground) {
        ForEach(PreviewBackground.allCases) { background in
          Text(background.rawValue).tag(background)
        }
      }
      .pickerStyle(.segmented)

      ZStack {
        (previewBackground == .light ? Color.white : Color(red: 0.12, green: 0.13, blue: 0.15))
        Image(nsImage: prepared.previewImage)
          .resizable()
          .interpolation(.high)
          .antialiased(true)
          .scaledToFit()
          .frame(width: 180 * scale, height: 180 * scale)
          .padding(12)
      }
      .frame(maxWidth: .infinity, minHeight: 230)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(.secondary.opacity(0.2))
      }

      if !prepared.validation.hasTransparentPixels {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text("这张图片没有检测到透明背景。继续使用时可能看到矩形背景。")
            .font(.callout)
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
      }

      if prepared.validation.requiresOptimization {
        Label(
          "图片尺寸较大，软件将创建最长边不超过 2048 px 的优化副本。",
          systemImage: "wand.and.stars"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }

      Form {
        TextField("名字", text: $name)
          .onChange(of: name) { _, newValue in
            if newValue.count > PetNameValidator.maximumLength {
              name = String(newValue.prefix(PetNameValidator.maximumLength))
            }
          }

        HStack {
          Text("桌面大小")
          Slider(
            value: $scale,
            in: PetConfiguration.default.minimumScale...PetConfiguration.default.maximumScale
          )
          Text("\(Int((scale * 100).rounded()))%")
            .monospacedDigit()
            .frame(width: 42, alignment: .trailing)
        }
      }
      .formStyle(.grouped)

      HStack {
        Button("取消", action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button("重新选择", action: onReselect)

        Spacer()

        if isSaving {
          ProgressView()
            .controlSize(.small)
        }

        Button(
          prepared.validation.hasTransparentPixels ? "使用这个角色" : "继续使用这个角色"
        ) {
          Task { await importAndUse() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!PetNameValidator.isValid(name) || isSaving)
      }
    }
    .padding(22)
    .frame(width: 520)
    .interactiveDismissDisabled(isSaving)
    .alert("导入未完成", isPresented: $isShowingError) {
      Button("好", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private func importAndUse() async {
    isSaving = true
    let safeName = PetNameValidator.normalized(name, fallback: prepared.suggestedName)
    let requestedScale = Double(scale)
    let result = await Task.detached(priority: .userInitiated) {
      Result {
        try importer.importPet(
          from: prepared,
          name: safeName,
          scale: requestedScale
        )
      }
    }.value
    isSaving = false

    switch result {
    case let .success(pet):
      do {
        try library.addAndSelect(pet)
        onImported()
      } catch {
        importer.discardImportedPet(pet)
        present(error)
      }
    case let .failure(error):
      present(error)
    }
  }

  private func present(_ error: Error) {
    errorMessage = (error as? LocalizedError)?.errorDescription
      ?? "无法保存角色，请检查磁盘空间后重试。"
    isShowingError = true
  }
}
