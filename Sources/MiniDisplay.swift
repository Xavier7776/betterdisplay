import AppKit
import CoreGraphics

struct ModeSpec: Codable, Equatable {
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double

    init(_ mode: CGDisplayMode) {
        width = mode.width; height = mode.height
        pixelWidth = mode.pixelWidth; pixelHeight = mode.pixelHeight
        refreshRate = mode.refreshRate
    }
    var hiDPI: Bool { pixelWidth == width * 2 && pixelHeight == height * 2 }
    func matches(_ mode: CGDisplayMode) -> Bool {
        width == mode.width && height == mode.height && pixelWidth == mode.pixelWidth &&
        pixelHeight == mode.pixelHeight && abs(refreshRate - mode.refreshRate) < 0.1
    }
    var title: String { "\(width) × \(height)  ·  \(hiDPI ? "HiDPI" : "标准")  ·  \(String(format: "%.0f", refreshRate)) Hz" }
    var pixels: String { "渲染像素 \(pixelWidth) × \(pixelHeight)" }
}

struct DisplayFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

func onlineDisplays() throws -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success else { throw DisplayFailure("无法读取显示器列表") }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { throw DisplayFailure("无法读取显示器列表") }
    return Array(ids.prefix(Int(count)))
}

func targetDisplay() throws -> CGDirectDisplayID {
    let matches = try onlineDisplays().filter {
        CGDisplayVendorNumber($0) == 19491 && CGDisplayModelNumber($0) == 10064 && CGDisplayIsBuiltin($0) == 0
    }
    guard matches.count == 1 else { throw DisplayFailure("需要连接唯一一台 OF27QT（4c23:2750）；当前找到 \(matches.count) 台") }
    let id = matches[0]
    guard CGDisplayIsActive(id) != 0 && CGDisplayIsInMirrorSet(id) == 0 else {
        throw DisplayFailure("OF27QT 当前未激活或处于镜像组；此版本只处理独立物理屏缩放")
    }
    return id
}

func allModes(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
    CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
}

func currentMode(_ id: CGDirectDisplayID) throws -> CGDisplayMode {
    guard let mode = CGDisplayCopyDisplayMode(id) else { throw DisplayFailure("显示器已断开，无法读取当前模式") }
    return mode
}

func selectableModes(_ modes: [CGDisplayMode], current: CGDisplayMode) -> [CGDisplayMode] {
    var byWidth: [Int: CGDisplayMode] = [:]
    for mode in modes {
        let spec = ModeSpec(mode)
        guard spec.hiDPI, mode.isUsableForDesktopGUI(), (1280...2560).contains(mode.width),
              mode.width % 16 == 0, mode.height * 16 == mode.width * 9,
              abs(mode.refreshRate - 100) < 0.1 else { continue }
        let old = byWidth[mode.width]
        if old == nil || mode.ioDisplayModeID == current.ioDisplayModeID ||
            (old!.ioDisplayModeID != current.ioDisplayModeID && old!.ioFlags != current.ioFlags && mode.ioFlags == current.ioFlags) {
            byWidth[mode.width] = mode
        }
    }
    return byWidth.values.sorted { $0.width < $1.width }
}

func resolve(_ spec: ModeSpec, id: CGDirectDisplayID) throws -> CGDisplayMode {
    let current = try currentMode(id)
    if spec.matches(current) { return current }
    let matches = allModes(id).filter { spec.matches($0) && $0.isUsableForDesktopGUI() }
    guard let mode = matches.first(where: { $0.ioFlags == current.ioFlags }) ?? matches.first else {
        throw DisplayFailure("系统未提供 \(spec.title)。请重新读取；若覆盖尚未激活，需先安装配置并重启。")
    }
    return mode
}

// Session changes survive this app exiting, but never replace the persistent system configuration.
func setMode(_ spec: ModeSpec, expectedDisplay: CGDirectDisplayID) throws {
    let id = try targetDisplay()
    guard id == expectedDisplay else { throw DisplayFailure("显示器连接已变化，请重新读取后再操作") }
    let mode = try resolve(spec, id: id)
    var configuration: CGDisplayConfigRef?
    var error = CGBeginDisplayConfiguration(&configuration)
    guard error == .success, let configuration else { throw DisplayFailure("无法开始显示事务：\(error.rawValue)") }
    error = CGConfigureDisplayWithDisplayMode(configuration, id, mode, nil)
    guard error == .success else {
        CGCancelDisplayConfiguration(configuration)
        throw DisplayFailure("系统拒绝该模式：\(error.rawValue)")
    }
    error = CGCompleteDisplayConfiguration(configuration, .forSession)
    guard error == .success else { throw DisplayFailure("显示事务提交失败：\(error.rawValue)") }
    guard spec.matches(try currentMode(id)) else { throw DisplayFailure("系统回读的模式与请求不符") }
}

final class WindowContent: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var displayID: CGDirectDisplayID = 0
    var modes: [CGDisplayMode] = []
    var initial: ModeSpec?
    var isApplying = false
    var modeWriter: (ModeSpec, CGDirectDisplayID) throws -> Void = { try setMode($0, expectedDisplay: $1) }
    var observer: NSObjectProtocol?
    let info = NSTextField(wrappingLabelWithString: "")
    let selection = NSTextField(labelWithString: "")
    let pixels = NSTextField(labelWithString: "")
    let status = NSTextField(wrappingLabelWithString: "正在读取…")
    let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    let restore = NSButton(title: "恢复启动时配置", target: nil, action: nil)
    let refresh = NSButton(title: "重新读取", target: nil, action: nil)
    let smoke = CommandLine.arguments.contains("--smoke-test")

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        reload()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if !self.isApplying { self.reload() }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if smoke { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.smokeTest() } }
    }

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 430), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "MiniDisplay · HiDPI 缩放"
        window.delegate = self
        window.contentView = WindowContent(frame: window.contentView!.bounds)
        window.center()
        let root = NSStackView()
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 15
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 25)
        ])
        let title = NSTextField(labelWithString: "OF27QT · 原生 HiDPI 缩放")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        root.addArrangedSubview(title)
        info.font = .systemFont(ofSize: 13); info.textColor = .secondaryLabelColor
        root.addArrangedSubview(info)
        selection.font = .monospacedDigitSystemFont(ofSize: 26, weight: .medium)
        root.addArrangedSubview(selection)
        pixels.textColor = .secondaryLabelColor
        root.addArrangedSubview(pixels)
        slider.target = self; slider.action = #selector(sliderChanged); slider.isContinuous = true
        slider.setAccessibilityLabel("HiDPI 逻辑分辨率")
        root.addArrangedSubview(slider)
        slider.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let ends = NSStackView(views: [NSTextField(labelWithString: "← 文字更大"), NSView(), NSTextField(labelWithString: "空间更多 →")])
        ends.distribution = .fill; ends.orientation = .horizontal
        root.addArrangedSubview(ends); ends.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        popup.target = self; popup.action = #selector(popupChanged)
        popup.setAccessibilityLabel("精确选择 HiDPI 分辨率")
        root.addArrangedSubview(popup); popup.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        restore.target = self; restore.action = #selector(restoreInitial)
        refresh.target = self; refresh.action = #selector(refreshPressed)
        root.addArrangedSubview(NSStackView(views: [restore, refresh]))
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        root.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        info.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let menu = NSMenu()
        let item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu(); appMenu.addItem(withTitle: "退出 MiniDisplay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; NSApp.mainMenu = menu
    }

    @objc func refreshPressed() { reload() }
    func reload() {
        do {
            let id = try targetDisplay()
            let current = try currentMode(id)
            if initial == nil { initial = ModeSpec(current) }
            displayID = id
            modes = selectableModes(allModes(id), current: current)
            popup.removeAllItems()
            popup.addItems(withTitles: modes.map { ModeSpec($0).title })
            slider.maxValue = Double(max(1, modes.count - 1))
            let index = modes.firstIndex { ModeSpec($0).matches(current) } ?? modes.indices.min(by: { abs(modes[$0].width - current.width) < abs(modes[$1].width - current.width) }) ?? 0
            if !modes.isEmpty { popup.selectItem(at: index); slider.integerValue = index; updateSelection() }
            info.stringValue = "物理屏原生输出 · 当前 \(ModeSpec(current).title)\n\(modes.count) 档 HiDPI（100 Hz），由系统完成缩放。"
            restore.isEnabled = initial != nil
            popup.isEnabled = !modes.isEmpty; slider.isEnabled = !modes.isEmpty
            status.stringValue = modes.isEmpty ? "没有找到配置所需的 HiDPI 模式。请先安装随附覆盖文件并重启。" : "调整即生效，无需确认。设置保留至本次登录会话结束。"
        } catch {
            modes = []; restore.isEnabled = false; popup.isEnabled = false; slider.isEnabled = false
            info.stringValue = "未找到可操作的 OF27QT 独立物理屏"
            status.stringValue = error.localizedDescription
        }
    }

    @objc func sliderChanged() {
        guard !modes.isEmpty else { return }
        let index = max(0, min(modes.count - 1, Int(slider.doubleValue.rounded())))
        slider.integerValue = index; popup.selectItem(at: index); updateSelection(); applySelected()
    }
    @objc func popupChanged() { slider.integerValue = popup.indexOfSelectedItem; updateSelection(); applySelected() }
    func updateSelection() {
        let index = popup.indexOfSelectedItem
        guard modes.indices.contains(index) else { return }
        let spec = ModeSpec(modes[index])
        selection.stringValue = "\(spec.width) × \(spec.height)"
        pixels.stringValue = "\(spec.pixels) · 2× HiDPI · 100 Hz"
    }
    @objc func applySelected() {
        guard modes.indices.contains(popup.indexOfSelectedItem) else { return }
        beginApply(ModeSpec(modes[popup.indexOfSelectedItem]))
    }
    @objc func restoreInitial() { if let initial { beginApply(initial) } }

    func beginApply(_ spec: ModeSpec) {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        var original: ModeSpec?
        do {
            original = ModeSpec(try currentMode(displayID))
            try modeWriter(spec, displayID)
            reload()
            status.stringValue = "已应用 \(spec.title)（本次登录会话有效）。"
        } catch {
            let reason = error.localizedDescription
            // A commit can succeed even when readback fails; restore only on an application error.
            var recovery = ""
            if let original {
                do {
                    try modeWriter(original, displayID)
                    recovery = "已恢复切换前的配置。"
                } catch {
                    recovery = "恢复失败：\(error.localizedDescription)"
                }
            }
            reload()
            status.stringValue = "应用失败：\(reason)\n\(recovery)"
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func smokeTest() {
        let realWriter = modeWriter
        do {
            let before = ModeSpec(try currentMode(displayID))
            guard let i = modes.firstIndex(where: { before.matches($0) }) else { throw DisplayFailure("当前模式未出现在列表中") }
            var requested: [ModeSpec] = []
            modeWriter = { spec, _ in requested.append(spec) }
            slider.doubleValue = 0; sliderChanged()
            guard requested.last?.width == 1280, requested.last?.height == 720 else { throw DisplayFailure("滑杆下界未自动应用") }
            slider.doubleValue = slider.maxValue; sliderChanged()
            guard requested.last?.width == 2544, requested.last?.height == 1431 else { throw DisplayFailure("滑杆上界未自动应用") }
            popup.selectItem(at: 0); popupChanged()
            guard requested.last?.width == 1280, requested.count == 3 else { throw DisplayFailure("下拉选择未自动应用") }
            modeWriter = { spec, _ in
                requested.append(spec)
                if requested.count == 4 { throw DisplayFailure("测试注入的应用失败") }
            }
            popup.selectItem(at: 0); popupChanged()
            guard requested.count == 5, requested.last == before, status.stringValue.contains("已恢复切换前") else {
                throw DisplayFailure("应用失败时没有恢复原配置")
            }
            print("PASS: slider lower/upper and popup actions immediately apply (recording writer); application error restores original")
            modeWriter = realWriter
            popup.selectItem(at: i); popupChanged()
            guard before.matches(try currentMode(displayID)), status.stringValue.hasPrefix("已应用") else { throw DisplayFailure("下拉选择真实自动应用/回读失败") }
            slider.integerValue = i; sliderChanged()
            guard before.matches(try currentMode(displayID)), status.stringValue.hasPrefix("已应用"), slider.isContinuous else {
                throw DisplayFailure("滑杆真实自动应用/回读失败")
            }
            restore.performClick(nil)
            guard before.matches(try currentMode(displayID)), status.stringValue.hasPrefix("已应用") else { throw DisplayFailure("恢复启动配置失败") }
            print("PASS: popup and continuous slider → real identical-mode commit/readback, no confirmation; restore startup config")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.captureOwnView()
                NSApp.terminate(nil)
            }
        } catch {
            modeWriter = realWriter
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    func captureOwnView() {
        guard let path = ProcessInfo.processInfo.environment["MINIDISPLAY_PREVIEW"], let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)) }
    }
}

func selfTest() throws {
    let id = try targetDisplay()
    let current = try currentMode(id)
    let spec = ModeSpec(current)
    let modes = selectableModes(allModes(id), current: current)
    guard modes.count == 80 else { throw DisplayFailure("本机已核对 80 档 HiDPI，实际 \(modes.count)") }
    guard modes.first?.width == 1280, modes.last?.width == 2544,
          modes.contains(where: { spec.matches($0) }),
          Set(modes.map(\.width)).count == modes.count,
          modes.allSatisfy({ ModeSpec($0).hiDPI && abs($0.refreshRate - 100) < 0.1 }),
          spec.matches(try resolve(spec, id: id)) else { throw DisplayFailure("模式筛选/去重/当前模式匹配失败") }
    let data = try JSONEncoder().encode(spec)
    guard try JSONDecoder().decode(ModeSpec.self, from: data) == spec else { throw DisplayFailure("配置序列化失败") }
    print("PASS: OF27QT \(id), independent native output; 80 unique HiDPI modes at 100 Hz, 1280×720…2544×1431; current \(spec.title), \(spec.pixels)")
}

if CommandLine.arguments.contains("--self-test") {
    do { try selfTest() } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
