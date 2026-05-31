import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSDraggingDestination {
  private var fileDropChannel: FlutterMethodChannel?
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
    configureFileDialogs(flutterViewController)
    configureFileDrop(flutterViewController)
    configureAppearance(flutterViewController)

    super.awakeFromNib()
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
