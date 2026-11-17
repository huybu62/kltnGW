// AutoClicker.swift — Auto Clicker cho macOS (13 Ventura trở lên, chạy tốt trên macOS 15 Sequoia)
// Build: ./build.sh   (cần Xcode Command Line Tools)

import SwiftUI
import AppKit
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Kiểu dữ liệu

enum MouseButton: String, CaseIterable, Identifiable, Codable {
    case left, right, middle
    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "Trái"
        case .right: return "Phải"
        case .middle: return "Giữa"
        }
    }
    var cgButton: CGMouseButton {
        switch self {
        case .left: return .left
        case .right: return .right
        case .middle: return .center
        }
    }
    var downType: CGEventType {
        switch self {
        case .left: return .leftMouseDown
        case .right: return .rightMouseDown
        case .middle: return .otherMouseDown
        }
    }
    var upType: CGEventType {
        switch self {
        case .left: return .leftMouseUp
        case .right: return .rightMouseUp
        case .middle: return .otherMouseUp
        }
    }
}

enum ClickType: String, CaseIterable, Identifiable, Codable {
    case single, double, triple
    var id: String { rawValue }
    var title: String {
        switch self {
        case .single: return "Đơn"
        case .double: return "Đúp"
        case .triple: return "Ba"
        }
    }
    var count: Int {
        switch self {
        case .single: return 1
        case .double: return 2
        case .triple: return 3
        }
    }
}

/// Cài đặt người dùng, được lưu vào UserDefaults.
struct ClickSettings: Codable, Equatable {
    var hours = 0
    var minutes = 0
    var seconds = 0
    var millis = 100
    var button: MouseButton = .left
    var clickType: ClickType = .single
    var repeatForever = true
    var repeatCount = 100
    var useFixedPosition = false
    var fixedX: Double = 0
    var fixedY: Double = 0
    var startDelay = 0
    var alwaysOnTop = true
    var cornerFailSafe = true

    var intervalMs: Int {
        ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis
    }
}

struct ClickConfig {
    let intervalNs: Int
    let startDelayMs: Int
    let button: MouseButton
    let clicksPerAction: Int
    let limit: Int?
    let fixedPoint: CGPoint?
    let cornerFailSafe: Bool
}

enum FinishReason {
    case completed, failSafe
}

// MARK: - Gửi sự kiện chuột

enum MouseClicker {
    /// Vị trí con trỏ hiện tại theo toạ độ Quartz (gốc ở góc trên-trái màn hình chính).
    static var cursorLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    static func click(at point: CGPoint, button: MouseButton, times: Int) {
        let source = CGEventSource(stateID: .hidSystemState)
        for i in 1...max(1, times) {
            guard
                let down = CGEvent(mouseEventSource: source, mouseType: button.downType,
                                   mouseCursorPosition: point, mouseButton: button.cgButton),
                let up = CGEvent(mouseEventSource: source, mouseType: button.upType,
                                 mouseCursorPosition: point, mouseButton: button.cgButton)
            else { continue }
            // clickState = 2/3 để hệ thống nhận diện double/triple click
            down.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            up.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Bộ máy click (chạy trên luồng nền, dùng DispatchSourceTimer cho chính xác)

final class ClickEngine {
    private let queue = DispatchQueue(label: "autoclicker.engine", qos: .userInteractive)
    private var timer: DispatchSourceTimer?   // chỉ truy cập trên main thread
    private let lock = NSLock()
    private var _count = 0
    private var _finished = false

    var onFinish: ((FinishReason) -> Void)?

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }

    func start(_ config: ClickConfig) {
        stop()
        lock.lock(); _count = 0; _finished = false; lock.unlock()

        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(deadline: .now() + .milliseconds(config.startDelayMs),
                   repeating: .nanoseconds(config.intervalNs),
                   leeway: .microseconds(100))
        t.setEventHandler { [weak self] in self?.tick(config) }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func finish(_ reason: FinishReason) {
        lock.lock()
        let already = _finished
        _finished = true
        lock.unlock()
        guard !already else { return }
        DispatchQueue.main.async { [weak self] in self?.onFinish?(reason) }
    }

    private func tick(_ c: ClickConfig) {
        lock.lock()
        let done = _finished || (c.limit.map { _count >= $0 } ?? false)
        lock.unlock()
        if done { return }

        let current = MouseClicker.cursorLocation
        if c.cornerFailSafe && current.x <= 2 && current.y <= 2 {
            finish(.failSafe)
            return
        }

        MouseClicker.click(at: c.fixedPoint ?? current, button: c.button, times: c.clicksPerAction)

        lock.lock()
        _count += 1
        let n = _count
        lock.unlock()

        if let limit = c.limit, n >= limit {
            finish(.completed)
        }
    }
}

// MARK: - Phím tắt toàn cục (Carbon — không cần quyền đặc biệt)

final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var installed = false
    private var nextID: UInt32 = 1

    func register(keyCode: Int, modifiers: Int = 0, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x41434C4B) /* 'ACLK' */, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
            actions[id] = action
        } else {
            NSLog("AutoClicker: không đăng ký được phím tắt keyCode=\(keyCode) (status \(status))")
        }
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &hkID)
            guard err == noErr else { return err }
            HotKeyCenter.shared.fire(hkID.id)
            return noErr
        }, 1, &spec, nil, nil)
    }
}

// MARK: - ViewModel

final class ClickerModel: ObservableObject {
    static let shared = ClickerModel()
    private static let defaultsKey = "AutoClickerSettings.v1"

    @Published var s: ClickSettings {
        didSet {
            if s.alwaysOnTop != oldValue.alwaysOnTop { applyWindowLevel() }
            save()
        }
    }
    @Published var isRunning = false
    @Published var clickCount = 0
    @Published var trusted = AXIsProcessTrusted()
    @Published var status = "Sẵn sàng"
    @Published var countdown: Int?

    private let engine = ClickEngine()
    private var uiTimer: Timer?
    private var startAt = Date()
    private var trustCheckTick = 0

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(ClickSettings.self, from: data) {
            s = saved
        } else {
            s = ClickSettings()
        }

        engine.onFinish = { [weak self] reason in
            guard let self, self.isRunning else { return }
            self.stop()
            switch reason {
            case .completed: self.status = "Hoàn tất \(self.clickCount) lần click"
            case .failSafe: self.status = "Dừng khẩn cấp (chuột ở góc màn hình)"
            }
        }

        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.uiTick() }
        RunLoop.main.add(t, forMode: .common)
        uiTimer = t
    }

    func setupHotKeys() {
        let toggle: () -> Void = { [weak self] in self?.toggle() }
        let capture: () -> Void = { [weak self] in self?.captureCursor() }
        HotKeyCenter.shared.register(keyCode: kVK_F6, action: toggle)
        HotKeyCenter.shared.register(keyCode: kVK_ANSI_S, modifiers: controlKey | optionKey, action: toggle)
        HotKeyCenter.shared.register(keyCode: kVK_F7, action: capture)
        HotKeyCenter.shared.register(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey, action: capture)
    }

    // MARK: Điều khiển

    func toggle() {
        isRunning ? stopByUser() : start()
    }

    func start() {
        guard !isRunning else { return }
        trusted = AXIsProcessTrusted()
        guard trusted else {
            status = "Chưa có quyền Trợ năng — hãy cấp quyền rồi thử lại"
            requestPermission()
            return
        }
        normalize()

        let cfg = ClickConfig(
            intervalNs: max(1, s.intervalMs) * 1_000_000,
            startDelayMs: s.startDelay * 1000,
            button: s.button,
            clicksPerAction: s.clickType.count,
            limit: s.repeatForever ? nil : s.repeatCount,
            fixedPoint: s.useFixedPosition ? CGPoint(x: s.fixedX, y: s.fixedY) : nil,
            cornerFailSafe: s.cornerFailSafe
        )
        clickCount = 0
        startAt = Date().addingTimeInterval(Double(s.startDelay))
        isRunning = true
        engine.start(cfg)
        uiTick()
    }

    func stopByUser() {
        guard isRunning else { return }
        stop()
        status = "Đã dừng sau \(clickCount) lần click"
    }

    private func stop() {
        engine.stop()
        isRunning = false
        clickCount = engine.count
    }

    private func normalize() {
        s.hours = max(0, s.hours)
        s.minutes = min(59, max(0, s.minutes))
        s.seconds = min(59, max(0, s.seconds))
        s.millis = min(999, max(0, s.millis))
        if s.intervalMs < 1 { s.millis = 1 }
        s.repeatCount = max(1, s.repeatCount)
    }

    // MARK: Vị trí

    func pickPosition() {
        guard countdown == nil, !isRunning else { return }
        countdown = 3
        scheduleCountdown()
    }

    private func scheduleCountdown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, let c = self.countdown else { return }
            if c <= 1 {
                self.countdown = nil
                self.captureCursor()
            } else {
                self.countdown = c - 1
                self.scheduleCountdown()
            }
        }
    }

    func captureCursor() {
        guard !isRunning else { return }
        let p = MouseClicker.cursorLocation
        s.fixedX = p.x.rounded()
        s.fixedY = p.y.rounded()
        s.useFixedPosition = true
        status = "Đã lấy toạ độ (\(Int(p.x)), \(Int(p.y)))"
        NSSound(named: NSSound.Name("Tink"))?.play()
    }

    // MARK: Quyền & cửa sổ

    func requestPermission() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(opts)
        if !trusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func applyWindowLevel() {
        let onTop = s.alwaysOnTop
        DispatchQueue.main.async {
            for w in NSApp.windows {
                w.level = onTop ? .floating : .normal
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func uiTick() {
        trustCheckTick += 1
        if trustCheckTick % 5 == 0 {
            let t = AXIsProcessTrusted()
            if t != trusted { trusted = t }
        }
        guard isRunning else { return }
        clickCount = engine.count
        let remain = startAt.timeIntervalSinceNow
        status = remain > 0 ? "Bắt đầu sau \(Int(remain.rounded(.up))) giây…" : "Đang chạy… (F6 để dừng)"
    }
}

// MARK: - Giao diện

struct NumberField: View {
    let unit: String
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 4) {
            TextField(unit, value: $value, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: ClickerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.trusted {
                permissionBanner
            }

            Group {
                GroupBox(label: Label("Khoảng cách giữa các lần click", systemImage: "timer")) {
                    HStack(spacing: 12) {
                        NumberField(unit: "giờ", value: $model.s.hours)
                        NumberField(unit: "phút", value: $model.s.minutes)
                        NumberField(unit: "giây", value: $model.s.seconds)
                        NumberField(unit: "ms", value: $model.s.millis)
                        Spacer()
                    }
                    .padding(6)
                }

                GroupBox(label: Label("Kiểu click", systemImage: "cursorarrow.click")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Nút chuột:", selection: $model.s.button) {
                            ForEach(MouseButton.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Picker("Kiểu nhấn:", selection: $model.s.clickType) {
                            ForEach(ClickType.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(6)
                }

                GroupBox(label: Label("Lặp lại", systemImage: "repeat")) {
                    HStack(alignment: .top) {
                        Picker("", selection: $model.s.repeatForever) {
                            Text("Lặp đến khi dừng").tag(true)
                            Text("Lặp số lần cố định:").tag(false)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()

                        HStack(spacing: 4) {
                            TextField("", value: $model.s.repeatCount, format: .number.grouping(.never))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("lần")
                        }
                        .padding(.top, 18)
                        .disabled(model.s.repeatForever)
                        Spacer()
                    }
                    .padding(6)
                }

                GroupBox(label: Label("Vị trí click", systemImage: "scope")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $model.s.useFixedPosition) {
                            Text("Vị trí con trỏ chuột hiện tại").tag(false)
                            Text("Vị trí cố định").tag(true)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()

                        HStack(spacing: 6) {
                            Text("X")
                            TextField("X", value: $model.s.fixedX, format: .number.grouping(.never))
                                .frame(width: 70)
                            Text("Y")
                            TextField("Y", value: $model.s.fixedY, format: .number.grouping(.never))
                                .frame(width: 70)
                            Button(model.countdown.map { "Lấy sau \($0)s…" } ?? "Chọn vị trí (3 giây)") {
                                model.pickPosition()
                            }
                            .disabled(model.countdown != nil)
                        }
                        .disabled(!model.s.useFixedPosition)

                        Text("Mẹo: rê chuột tới chỗ cần click rồi nhấn F7 (hoặc ⌃⌥P) để lấy toạ độ ngay.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                }

                GroupBox(label: Label("Tuỳ chọn khác", systemImage: "gearshape")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Stepper("Bắt đầu sau: \(model.s.startDelay) giây",
                                value: $model.s.startDelay, in: 0...60)
                        Toggle("Luôn hiển thị cửa sổ trên cùng", isOn: $model.s.alwaysOnTop)
                        Toggle("Dừng khẩn cấp khi đưa chuột vào góc trên-trái màn hình",
                               isOn: $model.s.cornerFailSafe)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
            }
            .disabled(model.isRunning)

            HStack(spacing: 10) {
                Button {
                    model.start()
                } label: {
                    Label("Bắt đầu (F6)", systemImage: "play.fill").frame(minWidth: 110)
                }
                .controlSize(.large)
                .disabled(model.isRunning)

                Button {
                    model.stopByUser()
                } label: {
                    Label("Dừng (F6)", systemImage: "stop.fill").frame(minWidth: 90)
                }
                .controlSize(.large)
                .disabled(!model.isRunning)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(model.status)
                        .font(.callout)
                        .foregroundColor(model.isRunning ? .green : .secondary)
                        .lineLimit(1)
                    Text("Đã click: \(model.clickCount)")
                        .font(.callout.monospacedDigit())
                }
            }

            Text("Phím tắt: F6 hoặc ⌃⌥S = bắt đầu/dừng  •  F7 hoặc ⌃⌥P = lấy vị trí chuột. Trên MacBook có thể cần giữ fn khi bấm F6/F7.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 480)
        .onAppear { model.applyWindowLevel() }
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cần cấp quyền Trợ năng (Accessibility)").bold()
                Text("Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Trợ năng → bật AutoClicker. Nếu đã bật mà vẫn báo, hãy xoá AutoClicker khỏi danh sách (nút −) rồi thêm lại.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Mở Cài đặt") { model.requestPermission() }
        }
        .padding(10)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(8)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ClickerModel.shared.setupHotKeys()
        ClickerModel.shared.applyWindowLevel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct AutoClickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var model = ClickerModel.shared

    var body: some Scene {
        Window("Auto Clicker", id: "main") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
