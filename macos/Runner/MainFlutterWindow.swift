import Cocoa
import FlutterMacOS
import JavaScriptCore

class MainFlutterWindow: NSWindow, NSDraggingDestination {
  #if DEBUG
  private var testingChannel: FlutterMethodChannel?
  #endif
  private var clipboardChannel: FlutterMethodChannel?
  private var codeChannel: FlutterMethodChannel?
  private let codeQueue = DispatchQueue(label: "devutils.javascript-code", qos: .userInitiated)
  // Created and accessed only on codeQueue, keeping JavaScriptCore thread-confined.
  private var codeContext: JSContext?
  private var fileDropChannel: FlutterMethodChannel?
  private var documentationChannel: FlutterMethodChannel?
  private var statusItem: NSStatusItem?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    let defaultSize = NSSize(width: 1280, height: 820)
    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 820)
    let origin = NSPoint(
      x: screenFrame.origin.x + (screenFrame.width - defaultSize.width) / 2,
      y: screenFrame.origin.y + (screenFrame.height - defaultSize.height) / 2
    )
    let frame = NSRect(origin: origin, size: defaultSize)
    self.setFrame(frame, display: true)
    self.minSize = NSSize(width: 1040, height: 700)

    RegisterGeneratedPlugins(registry: flutterViewController)
    configureJavascriptCode(flutterViewController)
    configureImageClipboard(flutterViewController)
    #if DEBUG
    testingChannel = FlutterMethodChannel(
      name: "devutils/testing", binaryMessenger: flutterViewController.engine.binaryMessenger)
    testingChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "activate" else { result(FlutterMethodNotImplemented); return }
      self?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      result(nil)
    }
    #endif
    configureFileDialogs(flutterViewController)
    configureFileDrop(flutterViewController)
    configureAppearance(flutterViewController)
    documentationChannel = FlutterMethodChannel(
      name: "devutils/documentation",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    documentationChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "ready" {
        self?.configureDocumentationMenu()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func configureImageClipboard(_ controller: FlutterViewController) {
    clipboardChannel = FlutterMethodChannel(
      name: "devutils/clipboard", binaryMessenger: controller.engine.binaryMessenger)
    clipboardChannel?.setMethodCallHandler { call, result in
      guard call.method == "copyImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let bytes = call.arguments as? FlutterStandardTypedData,
        let image = NSImage(data: bytes.data) else {
        result(FlutterError(code: "invalid_image", message: "Could not read image data.", details: nil))
        return
      }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      let copied = pasteboard.writeObjects([image])
      result(copied && pasteboard.canReadObject(forClasses: [NSImage.self], options: nil))
    }
  }

  private func configureJavascriptCode(_ controller: FlutterViewController) {
    codeChannel = FlutterMethodChannel(
      name: "devutils/javascript_code", binaryMessenger: controller.engine.binaryMessenger)
    codeChannel?.setMethodCallHandler { [weak self] call, result in
      guard let args = call.arguments as? [String: String], let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      if call.method == "initialize", let compiler = args["compiler"], let engine = args["engine"] {
        self.codeQueue.async {
          let context = JSContext()
          context?.evaluateScript(compiler)
          if context?.exception == nil { context?.evaluateScript(engine) }
          if let context, context.exception == nil {
            self.codeContext = context
            DispatchQueue.main.async { result(nil) }
          } else {
            DispatchQueue.main.async {
              result(FlutterError(code: "parser_init", message: "Could not load the offline code parser.", details: nil))
            }
          }
        }
        return
      }
      guard call.method == "process", let source = args["source"], let operation = args["operation"] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.codeQueue.async {
        guard let context = self.codeContext, context.exception == nil,
          let function = context.objectForKeyedSubscript("devutilsCodeOperation"),
          !function.isUndefined else {
          self.codeContext = nil
          DispatchQueue.main.async {
            result(FlutterError(code: "parser_init", message: "Could not load the offline code parser.", details: nil))
          }
          return
        }
        // Invoke a trusted parser function with source as data. Do not eval source.
        let value = function.call(withArguments: [source, operation, args["indentation"] ?? "2 spaces"])
        if let exception = context.exception {
          let message = exception.toString() ?? "Could not parse the source."
          context.exception = nil
          DispatchQueue.main.async {
            result(FlutterError(code: "parser_error", message: message, details: nil))
          }
        } else if let output = value?.toDictionary() {
          DispatchQueue.main.async { result(output) }
        } else {
          DispatchQueue.main.async {
            result(FlutterError(code: "parser_result", message: "The code parser returned no result.", details: nil))
          }
        }
      }
    }
  }

  func configureDocumentationMenu() {
    guard let helpMenu = NSApp.helpMenu
      ?? NSApp.mainMenu?.items.first(where: { $0.title == "Help" })?.submenu,
      helpMenu.item(withTitle: "Documentation") == nil else { return }
    NSApp.helpMenu = helpMenu
    let item = NSMenuItem(
      title: "Documentation", action: #selector(openDocumentation), keyEquivalent: "d")
    item.keyEquivalentModifierMask = [.command, .shift]
    item.target = self
    helpMenu.addItem(item)
  }

  @objc private func openDocumentation() {
    showMainWindow()
    documentationChannel?.invokeMethod("open", arguments: nil)
  }

  private func configureAppearance(_ flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "devutils/app_appearance",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      if call.method == "apply", let args = call.arguments as? [String: Any] {
        let showStatusBar = args["showStatusBar"] as? Bool ?? true
        let showDock = args["showDock"] as? Bool ?? true
        self.setStatusBarVisible(showStatusBar)
        self.setDockVisible(showDock)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setStatusBarVisible(_ visible: Bool) {
    if visible {
      if statusItem != nil { return }
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      if let button = item.button {
        if #available(macOS 11.0, *),
          let image = NSImage(
            systemSymbolName: "curlybraces", accessibilityDescription: "DevUtils")
        {
          image.isTemplate = true
          button.image = image
        } else {
          button.title = "{ }"
        }
      }
      let menu = NSMenu()
      let showItem = NSMenuItem(
        title: "Show DevUtils", action: #selector(showMainWindow), keyEquivalent: "")
      showItem.target = self
      let quitItem = NSMenuItem(
        title: "Quit DevUtils", action: #selector(quitApp), keyEquivalent: "q")
      quitItem.target = self
      menu.addItem(showItem)
      menu.addItem(NSMenuItem.separator())
      menu.addItem(quitItem)
      item.menu = menu
      statusItem = item
    } else {
      if let item = statusItem {
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
      }
    }
  }

  private func setDockVisible(_ visible: Bool) {
    NSApp.setActivationPolicy(visible ? .regular : .accessory)
    if visible {
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  @objc private func showMainWindow() {
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  private func configureFileDialogs(_ flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "devutils/file_dialogs",
      binaryMessenger: flutterViewController.engine.binaryMessenger)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }

      switch call.method {
      case "openFile":
        self.openFile(call: call, result: result)
      case "openDirectory":
        self.openDirectory(result: result)
      case "saveFile":
        self.saveFile(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureFileDrop(_ flutterViewController: FlutterViewController) {
    fileDropChannel = FlutterMethodChannel(
      name: "devutils/file_drop",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    registerForDraggedTypes([.fileURL])
  }

  private func openFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedFileTypes = extensions(from: call.arguments)
    result(panel.runModal() == .OK ? panel.url?.path : nil)
  }

  private func openDirectory(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    result(panel.runModal() == .OK ? panel.url?.path : nil)
  }

  private func saveFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let panel = NSSavePanel()
    panel.allowedFileTypes = extensions(from: call.arguments)
    if let suggestedName = args?["suggestedName"] as? String, !suggestedName.isEmpty {
      panel.nameFieldStringValue = suggestedName
    }
    if let directoryPath = args?["directoryPath"] as? String, !directoryPath.isEmpty {
      panel.directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
    }
    result(panel.runModal() == .OK ? panel.url?.path : nil)
  }

  private func extensions(from arguments: Any?) -> [String]? {
    guard
      let args = arguments as? [String: Any],
      let extensions = args["extensions"] as? [String],
      !extensions.isEmpty
    else {
      return nil
    }
    return extensions
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
      ? .copy
      : []
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard
      let urls = sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self],
        options: nil
      ) as? [URL],
      !urls.isEmpty
    else {
      return false
    }

    let location = sender.draggingLocation
    let viewHeight = contentViewController?.view.bounds.height ?? frame.height
    fileDropChannel?.invokeMethod(
      "filesDropped",
      arguments: [
        "paths": urls.map(\.path),
        "x": location.x,
        "y": viewHeight - location.y,
      ])
    return true
  }
}
