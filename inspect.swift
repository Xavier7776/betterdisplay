import AppKit
import CoreGraphics
var count: UInt32 = 0
CGGetOnlineDisplayList(0, nil, &count)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
CGGetOnlineDisplayList(count, &ids, &count)
let displays: [[String: Any]] = ids.map { id in
 let mode = CGDisplayCopyDisplayMode(id)!
 let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
 let b = CGDisplayBounds(id)
 let modes = (CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []).map { m in
  ["width": m.width, "height": m.height, "pixelWidth": m.pixelWidth, "pixelHeight": m.pixelHeight, "refreshRate": m.refreshRate, "modeID": m.ioDisplayModeID] as [String: Any]
 }
 return ["id": id, "name": screen?.localizedName ?? "", "builtin": CGDisplayIsBuiltin(id) != 0, "main": CGDisplayIsMain(id) != 0, "active": CGDisplayIsActive(id) != 0, "mirrorOf": CGDisplayMirrorsDisplay(id), "inMirrorSet": CGDisplayIsInMirrorSet(id) != 0, "rotation": CGDisplayRotation(id), "bounds": [b.origin.x,b.origin.y,b.width,b.height], "width": mode.width, "height": mode.height, "pixelWidth": mode.pixelWidth, "pixelHeight": mode.pixelHeight, "refreshRate": mode.refreshRate, "modeID": mode.ioDisplayModeID, "modes": modes]
}
let data = try JSONSerialization.data(withJSONObject: displays, options: [.prettyPrinted,.sortedKeys])
print(String(data: data, encoding: .utf8)!)
