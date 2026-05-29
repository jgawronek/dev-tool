import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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

    super.awakeFromNib()
  }
}
