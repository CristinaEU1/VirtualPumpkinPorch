// Virtual Pumpkin Porch 3.0: carved pumpkins that sit on your Mac.
//
// A row of candle-lit pumpkins sits on a "porch" just above the Dock, and a
// few little ones hop onto the top edge of whatever window is in front.
// Point at a pumpkin and it gets a fright. Now and then a bat flaps past.
// Clicks always pass straight through to whatever is underneath.
// Click the pumpkin in the menu bar to open the control panel.
//
// Inspired by Fall Desktop for Windows (github.com/starrlord/FallDesktop);
// this is a separate, original Mac app and shares no code with it.
//
// Data: optional, opt-in, and stored only on this Mac. Nothing is ever sent
// anywhere. See the "Your data" section of the panel and the README.
// MIT License, see LICENSE.
//
// Build:  bash build.sh

import AppKit
import ServiceManagement

let appVersion = "3.0"

// MARK: - Small helpers

func rnd(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat.random(in: a...b) }
func rndD(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b) }

let rgb = CGColorSpaceCreateDeviceRGB()

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: rgb, components: [r, g, b, a])!
}

/// Candle flicker, 0.4...1.0
func flicker(_ t: Double, _ ph: Double) -> CGFloat {
    let v = 0.78 + 0.12 * sin(t * 9.1 + ph) + 0.07 * sin(t * 23.7 + ph * 3.1) + 0.05 * sin(t * 3.3 + ph * 0.7)
    return CGFloat(max(0.4, min(1.0, v)))
}

func radial(_ c: CGContext, at p: CGPoint, radius: CGFloat, inner: [CGFloat], outer: [CGFloat]) {
    guard let g = CGGradient(colorSpace: rgb, colorComponents: inner + outer, locations: [0, 1], count: 2) else { return }
    c.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
}

/// A crescent between two quadratic curves that share their end points.
/// `down` = bulges downwards (a smile); otherwise it bulges upwards (a ^ eye).
func crescent(_ path: CGMutablePath, cx: CGFloat, y: CGFloat, w: CGFloat, outer: CGFloat, inner: CGFloat, down: Bool) {
    let s: CGFloat = down ? -2 : 2
    path.move(to: CGPoint(x: cx - w / 2, y: y))
    path.addQuadCurve(to: CGPoint(x: cx + w / 2, y: y), control: CGPoint(x: cx, y: y + s * outer))
    path.addQuadCurve(to: CGPoint(x: cx - w / 2, y: y), control: CGPoint(x: cx, y: y + s * inner))
    path.closeSubpath()
}

func polygon(_ path: CGMutablePath, _ pts: [CGPoint]) {
    guard let first = pts.first else { return }
    path.move(to: first)
    for p in pts.dropFirst() { path.addLine(to: p) }
    path.closeSubpath()
}

func duration(_ secs: Double) -> String {
    let m = Int(secs / 60)
    if m < 60 { return "\(m) min" }
    return "\(m / 60) h \(m % 60) min"
}

func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

/// Timestamps to the second, in local time with the UTC offset, e.g. 2026-11-01T00:49:12+02:00
let isoStamp: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone.current
    return f
}()

var macOSVersion: String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
}

// MARK: - Settings ("choices")

struct Choices: Codable {
    var faces = "cute"            // cute | spooky | mixed
    var count = 4                 // porch pumpkins per screen, 1...10
    var size = 1.0                // 0.6 ... 1.6
    var glow = 0.6                // 0 (off) ... 1
    var perch = true              // little pumpkins sit on windows
    var sitters = 2               // 1 ... 3
    var bats = "normal"           // off | rare | normal | flock
    var fright = "gentle"         // gentle | big
    var paused = false
    var hideInFullscreen = true
    var theme = "halloween"       // halloween | system | light | dark

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Choices()
        faces = try c.decodeIfPresent(String.self, forKey: .faces) ?? d.faces
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? d.count
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        glow = try c.decodeIfPresent(Double.self, forKey: .glow) ?? d.glow
        perch = try c.decodeIfPresent(Bool.self, forKey: .perch) ?? d.perch
        sitters = try c.decodeIfPresent(Int.self, forKey: .sitters) ?? d.sitters
        bats = try c.decodeIfPresent(String.self, forKey: .bats) ?? d.bats
        fright = try c.decodeIfPresent(String.self, forKey: .fright) ?? d.fright
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? d.paused
        hideInFullscreen = try c.decodeIfPresent(Bool.self, forKey: .hideInFullscreen) ?? d.hideInFullscreen
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? d.theme
    }
}

/// settings.json: the app's own bookkeeping, plus your choices when "Remember my choices" is on.
struct Settings: Codable {
    var schemaVersion = 1
    var installID = UUID().uuidString    // random, not linked to you or your Mac
    var trackingEnabled = false          // opt-in: off until you turn it on
    var consentAsked = false
    var rememberChoices = true
    var lastVersion: String? = nil
    var choices: Choices? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? d.schemaVersion
        installID = try c.decodeIfPresent(String.self, forKey: .installID) ?? d.installID
        trackingEnabled = try c.decodeIfPresent(Bool.self, forKey: .trackingEnabled) ?? false
        consentAsked = try c.decodeIfPresent(Bool.self, forKey: .consentAsked) ?? false
        rememberChoices = try c.decodeIfPresent(Bool.self, forKey: .rememberChoices) ?? true
        lastVersion = try c.decodeIfPresent(String.self, forKey: .lastVersion)
        choices = try c.decodeIfPresent(Choices.self, forKey: .choices)
    }
}

// MARK: - Data (kept on this Mac only, never sent anywhere)

struct VersionSeen: Codable {
    var version: String
    var firstSeen: Date
}

/// stats.json: running totals. Reads files written by earlier versions too.
struct Stats: Codable {
    var schemaVersion = 2
    var firstRun = Date()
    var launches = 0
    var secondsRunning: Double = 0
    var secondsPaused: Double = 0
    var secondsCute: Double = 0
    var secondsSpooky: Double = 0
    var secondsMixed: Double = 0
    var frights = 0
    var bats = 0
    var hops = 0
    var panelOpens = 0
    var secondsPanelOpen: Double = 0
    var settingChanges: [String: Int] = [:]
    var versionHistory: [VersionSeen] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = 2
        firstRun = try c.decodeIfPresent(Date.self, forKey: .firstRun) ?? Date()
        launches = try c.decodeIfPresent(Int.self, forKey: .launches) ?? 0
        secondsRunning = try c.decodeIfPresent(Double.self, forKey: .secondsRunning) ?? 0
        secondsPaused = try c.decodeIfPresent(Double.self, forKey: .secondsPaused) ?? 0
        secondsCute = try c.decodeIfPresent(Double.self, forKey: .secondsCute) ?? 0
        secondsSpooky = try c.decodeIfPresent(Double.self, forKey: .secondsSpooky) ?? 0
        secondsMixed = try c.decodeIfPresent(Double.self, forKey: .secondsMixed) ?? 0
        frights = try c.decodeIfPresent(Int.self, forKey: .frights) ?? 0
        bats = try c.decodeIfPresent(Int.self, forKey: .bats) ?? 0
        hops = try c.decodeIfPresent(Int.self, forKey: .hops) ?? 0
        panelOpens = try c.decodeIfPresent(Int.self, forKey: .panelOpens) ?? 0
        secondsPanelOpen = try c.decodeIfPresent(Double.self, forKey: .secondsPanelOpen) ?? 0
        settingChanges = try c.decodeIfPresent([String: Int].self, forKey: .settingChanges) ?? [:]
        versionHistory = try c.decodeIfPresent([VersionSeen].self, forKey: .versionHistory) ?? []
    }
}

/// One line of events.jsonl.
struct Event: Codable {
    var timestamp: String
    var installID: String
    var appVersion: String
    var event: String
    var setting: String? = nil
    var from: String? = nil
    var to: String? = nil
    var value: String? = nil
    var durationS: Double? = nil

    enum CodingKeys: String, CodingKey {
        case timestamp
        case installID = "install_id"
        case appVersion = "app_version"
        case event, setting, from, to, value
        case durationS = "duration_s"
    }
}

enum Store {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Virtual Pumpkin Porch", isDirectory: true)
    }

    /// Before the rename the data lived in ".../Virtual Pumpkin Porch". Move it once, so stats,
    /// events and choices carry over.
    static func moveOldFolderIfNeeded() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldFolder = base.appendingPathComponent("Pumpkin" + " Porch", isDirectory: true)
        guard fm.fileExists(atPath: oldFolder.path), !fm.fileExists(atPath: folder.path) else { return }
        try? fm.moveItem(at: oldFolder, to: folder)
    }
    static var statsFile: URL { folder.appendingPathComponent("stats.json") }
    static var settingsFile: URL { folder.appendingPathComponent("settings.json") }
    static var eventsFile: URL { folder.appendingPathComponent("events.jsonl") }

    static func ensureFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    static func loadStats() -> Stats? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: statsFile) else { return nil }
        return try? dec.decode(Stats.self, from: data)
    }

    static func save(_ s: Stats) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(s) else { return }
        ensureFolder()
        try? data.write(to: statsFile, options: .atomic)
    }

    static func loadSettings() -> Settings? {
        guard let data = try? Data(contentsOf: settingsFile) else { return nil }
        return try? JSONDecoder().decode(Settings.self, from: data)
    }

    static func save(_ s: Settings) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(s) else { return }
        ensureFolder()
        try? data.write(to: settingsFile, options: .atomic)
    }

    static func append(_ e: Event) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard var data = try? enc.encode(e) else { return }
        data.append(0x0A)
        ensureFolder()
        if let h = try? FileHandle(forWritingTo: eventsFile) {
            h.seekToEndOfFile()
            h.write(data)
            h.closeFile()
        } else {
            try? data.write(to: eventsFile)
        }
    }

    static func loadEvents() -> [Event] {
        guard let text = try? String(contentsOf: eventsFile, encoding: .utf8) else { return [] }
        let dec = JSONDecoder()
        return text.split(separator: "\n").compactMap { try? dec.decode(Event.self, from: Data($0.utf8)) }
    }
}

let dataInfoText = """
When data tracking is on, Virtual Pumpkin Porch records on this Mac: when the app starts and stops; \
every setting you change (from what to what, and when, to the second); how often this panel \
is opened and for how long; pumpkin frights, bats and hops; and the app version, macOS version \
and number of screens. Everything is tagged with a random ID, not your name.

It never records which apps, windows, websites or files you use, and never sends anything \
anywhere. The data stays on your Mac. You can keep it for yourself, or choose to share an \
export with the app's author for research.
"""

// MARK: - Model

enum Face { case cute, happy, sleepy, classic, toothy, surprised }

final class Pumpkin {
    static var scale: CGFloat = 1

    var x: CGFloat              // centre, global screen coordinates
    var y: CGFloat              // bottom
    let baseSize: CGFloat
    var fixedSize: CGFloat? = nil
    var restFace: Face
    var face: Face
    let tint: CGFloat
    let phase: Double
    let stemTilt: CGFloat
    let isPercher: Bool
    var isPanelSitter = false     // the one that sits on the control panel

    var wobble: CGFloat = 0
    var wobbleVel: CGFloat = 0
    var surprisedUntil: Double = 0
    var hovering = false
    var alpha: CGFloat = 1
    var targetAlpha: CGFloat = 1

    // hopping
    var hopFrom = CGPoint.zero
    var hopTo = CGPoint.zero
    var hopT: Double = 1        // >= 1: not hopping
    var hopArc: CGFloat = 40

    init(x: CGFloat, y: CGFloat, baseSize: CGFloat, face: Face, isPercher: Bool) {
        self.x = x; self.y = y; self.baseSize = baseSize
        self.restFace = face; self.face = face
        self.tint = rnd(0, 1)
        self.phase = rndD(0, 100)
        self.stemTilt = rnd(-0.06, 0.06)
        self.isPercher = isPercher
    }

    var size: CGFloat { fixedSize ?? baseSize * Pumpkin.scale }
    var height: CGFloat { size * 0.78 }

    /// Where it was last painted, so exactly that area gets cleared when it moves.
    var painted: CGRect?

    /// Everything we might paint: the candle glow (up to 1.3 x size from the middle),
    /// shadow, stem, wobble and the sleepy "z"s, with room to spare.
    var bounds: CGRect {
        let r = size * 1.45
        let mid = y + height * 0.5
        return CGRect(x: x - r, y: mid - r, width: 2 * r, height: 2 * r + size * 0.45)
    }

    var hitBox: CGRect { CGRect(x: x - size / 2, y: y, width: size, height: height) }

    func hop(to p: CGPoint) {
        hopFrom = CGPoint(x: x, y: y)
        hopTo = p
        hopT = 0
        hopArc = 30 + min(120, hypot(p.x - x, p.y - y) * 0.15)
    }
}

final class Bat {
    var x: CGFloat
    var y: CGFloat
    let baseY: CGFloat
    let vx: CGFloat
    let size: CGFloat
    let phase: Double
    let minX: CGFloat
    let maxX: CGFloat

    init(screen: CGRect, dir: CGFloat, baseY: CGFloat, lag: CGFloat) {
        size = rnd(20, 32)
        x = dir > 0 ? screen.minX - 60 - lag : screen.maxX + 60 + lag
        self.baseY = baseY
        y = baseY
        vx = dir * rnd(150, 230)
        phase = rndD(0, 100)
        minX = screen.minX - 90
        maxX = screen.maxX + 90
    }

    var painted: CGRect?
    var bounds: CGRect { CGRect(x: x - size * 1.3, y: y - size * 1.0, width: size * 2.6, height: size * 2.1) }
    var gone: Bool { (vx > 0 && x > maxX) || (vx < 0 && x < minX) }
}

// MARK: - Overlay window (one per screen)

final class OverlayView: NSView {
    weak var controller: AppController?
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext, let ctl = controller, let win = window else { return }
        c.clear(dirtyRect)
        let o = win.frame.origin
        let globalDirty = dirtyRect.offsetBy(dx: o.x, dy: o.y)
        let t = ctl.now
        let glow = CGFloat(ctl.opt.glow)
        c.saveGState()
        c.translateBy(x: -o.x, y: -o.y)
        for p in ctl.pumpkins where p.alpha > 0 && p.bounds.intersects(globalDirty) {
            ctl.drawPumpkin(c, p, t: t, glow: glow)
        }
        for b in ctl.bats where b.bounds.intersects(globalDirty) {
            ctl.drawBat(c, b, t: t)
        }
        c.restoreGState()
    }
}

func makeOverlay(for screen: NSScreen, controller: AppController) -> NSWindow {
    let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.setFrame(screen.frame, display: false)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.ignoresMouseEvents = true
    w.level = .floating
    w.isReleasedWhenClosed = false
    let v = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
    v.controller = controller
    w.contentView = v
    return w
}

// MARK: - App

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var windows: [NSWindow] = []
    var pumpkins: [Pumpkin] = []
    var bats: [Bat] = []
    var timer: Timer?
    var statusItem: NSStatusItem!

    var settings = Settings()
    var opt = Choices()
    var stats = Stats()
    var tracking: Bool { settings.trackingEnabled }

    let launchDate = Date()
    var start = Date()
    var lastTick: Double = 0
    var lastPerchCheck: Double = -1
    var lastFullscreenCheck: Double = -1
    var lastSave: Double = 0
    var lastLabelUpdate: Double = 0
    var nextBat: Double = 4
    var pausedAt: Date?
    var previousVersion: String?

    // panel
    var panel: NSWindow?
    var panelOpenedAt: Date?
    var pendingSlider: [String: String] = [:]
    var faceButtons: [NSButton] = []
    var countLabel: NSTextField?
    var sitterControl: NSSegmentedControl?
    var statsLabels: [NSTextField] = []

    var now: Double { Date().timeIntervalSince(start) }

    // MARK: launch

    func applicationDidFinishLaunching(_ note: Notification) {
        Store.moveOldFolderIfNeeded()
        let oldStats = Store.loadStats()
        if let s = Store.loadSettings() {
            settings = s
            previousVersion = s.lastVersion
        } else if oldStats != nil {
            previousVersion = "2.1 or earlier"     // stats from before 3.0, no settings file yet
        }
        if let s = oldStats { stats = s }          // totals from earlier versions are kept
        if settings.rememberChoices, let c = settings.choices { opt = c }
        Pumpkin.scale = CGFloat(opt.size)

        buildStatusItem()
        buildMainMenu()
        rebuildWindows()
        buildPumpkins()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        scheduleNextBat(from: 3)
        if opt.paused { pausedAt = Date() } else { startTimer() }

        if settings.consentAsked {
            recordLaunch()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.askConsent() }
        }
    }

    func recordLaunch() {
        if tracking {
            stats.launches += 1
            if let prev = previousVersion, prev != appVersion,
               !stats.versionHistory.contains(where: { $0.version == prev }) {
                stats.versionHistory.append(VersionSeen(version: prev, firstSeen: stats.firstRun))
            }
            if !stats.versionHistory.contains(where: { $0.version == appVersion }) {
                stats.versionHistory.append(VersionSeen(version: appVersion, firstSeen: Date()))
            }
            logEvent("session_start", value: context())
            if let prev = previousVersion, prev != appVersion {
                logEvent("app_updated", from: prev, to: appVersion)
            }
            Store.save(stats)
        }
        settings.lastVersion = appVersion
        saveSettings()
    }

    func context() -> String {
        "macOS \(macOSVersion); screens \(NSScreen.screens.count); remember_choices \(settings.rememberChoices); " +
        "faces \(opt.faces); count \(opt.count); size \(fmt(opt.size)); glow \(fmt(opt.glow)); " +
        "sit_on_windows \(opt.perch); sitters \(opt.sitters); bats \(opt.bats); fright \(opt.fright); " +
        "paused \(opt.paused); hide_in_fullscreen \(opt.hideInFullscreen); theme \(opt.theme)"
    }

    func askConsent() {
        let a = NSAlert()
        a.messageText = "🎃 Help with research? (optional)"
        a.informativeText = dataInfoText + "\n\nData tracking is off until you turn it on, and you can change your mind anytime in the Virtual Pumpkin Porch panel."
        a.addButton(withTitle: "Turn on data tracking")
        a.addButton(withTitle: "Keep it off")
        NSApp.activate(ignoringOtherApps: true)
        let answer = a.runModal()
        settings.consentAsked = true
        if answer == .alertFirstButtonReturn {
            settings.trackingEnabled = true
            logEvent("tracking_on", value: context())
        }
        recordLaunch()
        refreshPanel()
    }

    func applicationWillTerminate(_ note: Notification) {
        closePanelBookkeeping()
        if let p = pausedAt { stats.secondsPaused += tracking ? Date().timeIntervalSince(p) : 0 }
        logEvent("session_end", duration: Date().timeIntervalSince(launchDate))
        if tracking { Store.save(stats) }
        saveSettings()
    }

    // MARK: data

    func logEvent(_ name: String, setting: String? = nil, from: String? = nil, to: String? = nil,
             value: String? = nil, duration: Double? = nil) {
        guard tracking else { return }
        var e = Event(timestamp: isoStamp.string(from: Date()), installID: settings.installID,
                      appVersion: appVersion, event: name)
        e.setting = setting; e.from = from; e.to = to; e.value = value
        if let d = duration { e.durationS = (d * 10).rounded() / 10 }
        Store.append(e)
    }

    /// A setting changed: count it, log it, and save the choices.
    func record(_ key: String, from: String, to: String) {
        if tracking && from != to {
            stats.settingChanges[key, default: 0] += 1
            logEvent("setting_changed", setting: key, from: from, to: to)
        }
        saveSettings()
    }

    /// Sliders send many updates while dragging; record one change when the drag ends.
    func sliderChange(_ key: String, before: String, after: String) {
        if pendingSlider[key] == nil { pendingSlider[key] = before }
        let type = NSApp.currentEvent?.type
        let dragging = type == .leftMouseDragged || type == .leftMouseDown
        if !dragging, let from = pendingSlider[key] {
            pendingSlider[key] = nil
            record(key, from: from, to: after)
        }
    }

    func saveSettings() {
        settings.choices = settings.rememberChoices ? opt : nil
        Store.save(settings)
    }

    func setTracking(_ on: Bool) {
        guard on != tracking else { return }
        if on {
            settings.trackingEnabled = true
            settings.consentAsked = true
            logEvent("tracking_on", value: context())
            Store.save(stats)
        } else {
            logEvent("tracking_off")
            Store.save(stats)
            settings.trackingEnabled = false
        }
        saveSettings()
    }

    @objc func openDataFolder() {
        Store.ensureFolder()
        if tracking { Store.save(stats) }
        _ = NSWorkspace.shared.open(Store.folder)
    }

    func csvField(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    @objc func exportData() {
        if tracking { Store.save(stats) }
        let events = Store.loadEvents()
        let hasStats = FileManager.default.fileExists(atPath: Store.statsFile.path)
        guard hasStats || !events.isEmpty else {
            alert("Nothing to export yet", "No data has been recorded on this Mac. Turn on data tracking to start recording.")
            return
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let dest = desktop.appendingPathComponent("Virtual Pumpkin Porch data \(df.string(from: Date()))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        // events.csv
        var csv = "timestamp,install_id,app_version,event,setting,from,to,value,duration_s\n"
        for e in events {
            let cols = [e.timestamp, e.installID, e.appVersion, e.event, e.setting ?? "", e.from ?? "",
                        e.to ?? "", e.value ?? "", e.durationS.map { String($0) } ?? ""]
            csv += cols.map { self.csvField($0) }.joined(separator: ",") + "\n"
        }
        try? csv.write(to: dest.appendingPathComponent("events.csv"), atomically: true, encoding: .utf8)

        // events.json
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(events) {
            try? data.write(to: dest.appendingPathComponent("events.json"))
        }
        // totals.json
        if hasStats { try? FileManager.default.copyItem(at: Store.statsFile, to: dest.appendingPathComponent("totals.json")) }

        let readme = """
        Virtual Pumpkin Porch data export
        Exported: \(isoStamp.string(from: Date()))
        App version: \(appVersion)
        Anonymous install ID: \(settings.installID)

        This folder contains only what Virtual Pumpkin Porch recorded on this Mac:
        - events.csv / events.json: one row per event, timestamps to the second with UTC offset
        - totals.json: running totals (time running, frights, bats, hops, panel use, setting changes, versions)

        Events: session_start, session_end, app_updated, setting_changed, panel_open, panel_close,
        panel_minimize, panel_restore, pause, resume, fright, bat, hop, tracking_on, tracking_off,
        data_exported.

        No names, email addresses, file names, window titles, app names or websites are recorded.
        The install ID is random and is not derived from your Mac or your accounts.

        Please review these files before sharing them. Sharing is entirely your choice.
        """
        try? readme.write(to: dest.appendingPathComponent("about-this-export.txt"), atomically: true, encoding: .utf8)
        logEvent("data_exported")
        NSWorkspace.shared.activateFileViewerSelecting([dest])
    }

    @objc func deleteData() {
        let a = NSAlert()
        a.messageText = "Delete all recorded data?"
        a.informativeText = "This permanently deletes your stats and event log from this Mac and gives this installation a new random ID. Your choices are kept. Exports you saved elsewhere are not touched."
        a.addButton(withTitle: "Delete")
        a.addButton(withTitle: "Cancel")
        a.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.removeItem(at: Store.statsFile)
        try? FileManager.default.removeItem(at: Store.eventsFile)
        stats = Stats()
        settings.installID = UUID().uuidString
        if tracking { Store.save(stats) }
        saveSettings()
        updateStatsLabels()
    }

    func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    // MARK: start at login (macOS 13+)

    var loginAvailable: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    var loginEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    func setLogin(_ on: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if on && SMAppService.mainApp.status == .requiresApproval {
                alert("One more step", "Allow Virtual Pumpkin Porch in System Settings › General › Login Items.")
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            alert("Couldn't change Start at login",
                  "Tip: move Virtual Pumpkin Porch.app into your Applications folder first, then try again.\n\n\(error.localizedDescription)")
        }
    }

    // MARK: setup

    func rebuildWindows() {
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows = NSScreen.screens.map { makeOverlay(for: $0, controller: self) }
        applyFullscreenBehaviour()
        if !opt.paused { windows.forEach { $0.orderFrontRegardless() } }
    }

    /// The overlays may always join full-screen spaces; whether they show there is
    /// decided screen by screen in updateFullscreenHiding().
    func applyFullscreenBehaviour() {
        let b: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        windows.forEach { $0.collectionBehavior = b }
        updateFullscreenHiding()
    }

    /// Screens (as indexes into `windows`) that are showing a full-screen app, video, game
    /// or presentation right now. Only windows of the current space are listed, so a window
    /// that fills its screen means that screen is in full screen.
    func fullScreenCovered() -> Set<Int> {
        var covered = Set<Int>()
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return covered }
        let me = ProcessInfo.processInfo.processIdentifier
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != me,
                  let bd = info[kCGWindowBounds as String] as? NSDictionary,
                  let q = CGRect(dictionaryRepresentation: bd as CFDictionary),
                  q.width > 100, q.height > 100 else { continue }
            if let a = info[kCGWindowAlpha as String] as? Double, a < 0.1 { continue }
            // Quartz measures from the top-left of the main screen; AppKit from the bottom-left.
            let r = CGRect(x: q.minX, y: primary.frame.height - q.maxY, width: q.width, height: q.height)
            for (i, w) in windows.enumerated() where !covered.contains(i) && fillsScreen(r, w) {
                covered.insert(i)
            }
        }
        return covered
    }

    /// True when the window fills the screen: exactly, or (on Macs with a camera notch)
    /// everything below the notch, which is how full-screen apps usually sit there.
    func fillsScreen(_ r: CGRect, _ overlay: NSWindow) -> Bool {
        let f = overlay.frame
        func same(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 2 }
        guard same(r.minX, f.minX), same(r.width, f.width), same(r.minY, f.minY) else { return false }
        if same(r.height, f.height) { return true }
        if #available(macOS 12.0, *), let screen = overlay.screen {
            let notch = screen.safeAreaInsets.top
            if notch > 0 && same(r.height, f.height - notch) { return true }
        }
        return false
    }

    /// Asks macOS which displays are currently showing a full-screen space. This is the
    /// same signal window managers such as Amethyst and yabai rely on. Returns nil if the
    /// call isn't available, in which case only the window-size check is used.
    func fullScreenDisplays() -> (all: Bool, ids: Set<String>)? {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let connSym = dlsym(rtldDefault, "CGSMainConnectionID"),
              let spacesSym = dlsym(rtldDefault, "CGSCopyManagedDisplaySpaces") else { return nil }
        typealias ConnFn = @convention(c) () -> Int32
        typealias SpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
        let conn = unsafeBitCast(connSym, to: ConnFn.self)()
        guard let raw = unsafeBitCast(spacesSym, to: SpacesFn.self)(conn)?.takeRetainedValue(),
              let displays = (raw as NSArray) as? [[String: Any]] else { return nil }
        var all = false
        var ids = Set<String>()
        for d in displays {
            guard let current = d["Current Space"] as? [String: Any],
                  let type = (current["type"] as? NSNumber)?.intValue, type == 4 else { continue }  // 4 = full screen
            let id = (d["Display Identifier"] as? String ?? "Main").uppercased()
            if id == "MAIN" { all = true } else { ids.insert(id) }
        }
        return (all, ids)
    }

    /// The display's identifier, in the same form macOS uses for its spaces.
    func displayUUID(_ screen: NSScreen) -> String? {
        guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(n.uint32Value))?.takeRetainedValue(),
              let str = CFUUIDCreateString(nil, uuid) else { return nil }
        return (str as String).uppercased()
    }

    func updateFullscreenHiding() {
        var covered = Set<Int>()
        if opt.hideInFullscreen {
            covered = fullScreenCovered()
            if let fs = fullScreenDisplays() {
                for (i, w) in windows.enumerated() {
                    guard let screen = NSScreen.screens.first(where: { $0.frame == w.frame }) else { continue }
                    if fs.all || displayUUID(screen).map({ fs.ids.contains($0) }) == true { covered.insert(i) }
                }
            }
        }
        for (i, w) in windows.enumerated() {
            let a: CGFloat = covered.contains(i) ? 0 : 1
            if w.alphaValue != a { w.alphaValue = a }
        }
    }

    func faceList() -> [Face] {
        switch opt.faces {
        case "spooky": return [.classic, .toothy, .classic, .happy]
        case "mixed": return [.cute, .happy, .sleepy, .classic, .toothy]
        default: return [.cute, .happy, .sleepy, .cute]
        }
    }

    func porch(on screen: NSScreen) -> [Pumpkin] {
        pumpkins.filter { !$0.isPercher && !$0.isPanelSitter && screen.frame.contains(CGPoint(x: $0.x, y: $0.y + 1)) }
    }

    /// Tries to place one more porch pumpkin on a screen without overlapping the others.
    func placePorchPumpkin(on screen: NSScreen, among existing: [Pumpkin]) -> Pumpkin? {
        let vf = screen.visibleFrame
        for _ in 0..<60 {
            let base = rnd(44, 72)
            let x = rnd(vf.minX + 50, vf.maxX - 50)
            let clash = existing.contains { abs($0.x - x) < ($0.baseSize + base) * Pumpkin.scale / 2 + 14 }
            if !clash { return Pumpkin(x: x, y: vf.minY + 2, baseSize: base, face: faceList().randomElement()!, isPercher: false) }
        }
        return nil
    }

    func buildPumpkins() {
        var perchers = pumpkins.filter { $0.isPercher }
        var panelSitter = pumpkins.first { $0.isPanelSitter }
        if panelSitter == nil {
            let p = Pumpkin(x: -1000, y: -1000, baseSize: 38, face: faceList().randomElement()!, isPercher: false)
            p.isPanelSitter = true
            p.alpha = 0; p.targetAlpha = 0
            panelSitter = p
        }
        pumpkins = []
        for screen in NSScreen.screens {
            var mine: [Pumpkin] = []
            while mine.count < opt.count, let p = placePorchPumpkin(on: screen, among: mine) { mine.append(p) }
            pumpkins.append(contentsOf: mine)
        }
        if perchers.isEmpty {
            for s in [40, 32, 36] as [CGFloat] {
                let p = Pumpkin(x: -1000, y: -1000, baseSize: s, face: faceList().randomElement()!, isPercher: true)
                p.alpha = 0; p.targetAlpha = 0
                perchers.append(p)
            }
        }
        pumpkins.append(contentsOf: perchers)
        if let ps = panelSitter { pumpkins.append(ps) }
        redrawAll()
    }

    /// Adds or removes porch pumpkins to match the count, leaving the others where they are.
    func adjustCount() {
        for screen in NSScreen.screens {
            var mine = porch(on: screen)
            while mine.count > opt.count, let last = mine.popLast() {
                invalidate(last.painted ?? last.bounds)
                pumpkins.removeAll { $0 === last }
            }
            while mine.count < opt.count, let p = placePorchPumpkin(on: screen, among: mine) {
                mine.append(p)
                pumpkins.insert(p, at: 0)
                invalidate(p.bounds)
            }
        }
    }

    func refaceAll() {
        for p in pumpkins { p.restFace = faceList().randomElement()!; p.face = p.restFace }
        redrawAll()
    }

    @objc func screensChanged() { rebuildWindows(); buildPumpkins() }

    // MARK: animation

    func startTimer() {
        timer?.invalidate()
        lastTick = now
        let t = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func invalidate(_ r: CGRect) {
        for w in windows where w.frame.intersects(r) {
            w.contentView?.setNeedsDisplay(r.offsetBy(dx: -w.frame.minX, dy: -w.frame.minY))
        }
    }

    func redrawAll() { windows.forEach { $0.contentView?.needsDisplay = true } }

    /// Clears wherever the pumpkin was last drawn and paints it where it is now.
    /// Whatever moved it (a hop, a window being dragged, a fade), nothing is left behind.
    func repaint(_ p: Pumpkin) {
        let current: CGRect? = p.alpha > 0 ? p.bounds : nil
        switch (p.painted, current) {
        case let (old?, new?): invalidate(old.union(new))
        case let (old?, nil): invalidate(old)
        case let (nil, new?): invalidate(new)
        default: break
        }
        p.painted = current
    }

    func scheduleNextBat(from t: Double) {
        switch opt.bats {
        case "off": nextBat = .infinity
        case "rare": nextBat = t + rndD(60, 120)
        case "flock": nextBat = t + rndD(15, 35)
        default: nextBat = t + rndD(18, 45)
        }
    }

    func spawnBats() {
        guard let screen = NSScreen.screens.randomElement()?.frame else { return }
        let n = opt.bats == "flock" ? Int.random(in: 3...5) : 1
        let dir: CGFloat = Bool.random() ? 1 : -1
        let y = screen.minY + screen.height * rnd(0.45, 0.8)
        for i in 0..<n {
            bats.append(Bat(screen: screen, dir: dir, baseY: y + rnd(-40, 40), lag: CGFloat(i) * rnd(40, 70)))
            if tracking { stats.bats += 1 }
            logEvent("bat")
        }
    }

    @objc func tick() {
        let t = now
        let dt = CGFloat(min(0.1, t - lastTick))
        lastTick = t
        let mouse = NSEvent.mouseLocation

        if tracking {
            let d = Double(dt)
            stats.secondsRunning += d
            switch opt.faces {
            case "spooky": stats.secondsSpooky += d
            case "mixed": stats.secondsMixed += d
            default: stats.secondsCute += d
            }
            if t - lastSave > 30 { lastSave = t; Store.save(stats) }
        }
        if panel?.isVisible == true && t - lastLabelUpdate > 1 { lastLabelUpdate = t; updateStatsLabels() }

        if t - lastPerchCheck > 0.1 { lastPerchCheck = t; updatePerch(); updatePanelSitter() }
        if t - lastFullscreenCheck > 0.3 { lastFullscreenCheck = t; updateFullscreenHiding() }

        for p in pumpkins {
            // hop
            if p.hopT < 1 {
                p.hopT = min(1, p.hopT + Double(dt) / 0.5)
                let k = CGFloat(p.hopT)
                let e = k * k * (3 - 2 * k)
                p.x = p.hopFrom.x + (p.hopTo.x - p.hopFrom.x) * e
                p.y = p.hopFrom.y + (p.hopTo.y - p.hopFrom.y) * e + sin(.pi * k) * p.hopArc
                if p.hopT >= 1 { p.wobbleVel += rnd(-1.5, 1.5) }   // a little bump on landing
            }
            // fright when the pointer touches it
            let over = p.alpha > 0.5 && p.hitBox.contains(mouse)
            if over && !p.hovering {
                if tracking { stats.frights += 1 }
                logEvent("fright")
                p.face = .surprised
                p.surprisedUntil = t + 1.6
                if opt.fright == "big" {
                    p.wobbleVel += (Bool.random() ? 1 : -1) * rnd(7, 9)
                    if p.hopT >= 1 { p.hop(to: CGPoint(x: p.x, y: p.y)); p.hopArc = 34 }
                } else {
                    p.wobbleVel += (Bool.random() ? 1 : -1) * rnd(3.5, 5)
                }
            }
            p.hovering = over
            if p.face == .surprised && t > p.surprisedUntil && !over { p.face = p.restFace }
            // an idle wiggle now and then
            if CGFloat.random(in: 0...1) < dt * 0.04 { p.wobbleVel += rnd(-1.2, 1.2) }
            // springy wobble
            p.wobbleVel += (-70 * p.wobble - 5 * p.wobbleVel) * dt
            p.wobble += p.wobbleVel * dt
            // fade
            p.alpha += (p.targetAlpha - p.alpha) * min(1, dt * 6)
            if p.targetAlpha == 0 && p.alpha < 0.02 { p.alpha = 0 }   // fully gone, no faint ghost left behind
            repaint(p)
        }

        if t > nextBat {
            spawnBats()
            scheduleNextBat(from: t)
        }
        for b in bats {
            b.x += b.vx * dt
            b.y = b.baseY + CGFloat(sin(t * 1.7 + b.phase)) * 22
            let r = b.bounds
            invalidate(b.painted.map { $0.union(r) } ?? r)
            b.painted = r
        }
        for b in bats where b.gone { if let r = b.painted { invalidate(r) } }
        bats.removeAll { $0.gone }
    }

    /// Finds the top edge of the frontmost ordinary window of another app.
    func frontWindowTop() -> (minX: CGFloat, maxX: CGFloat, top: CGFloat)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != me,
                  let bd = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
                  r.width > 260, r.height > 140 else { continue }
            if let a = info[kCGWindowAlpha as String] as? Double, a < 0.1 { continue }
            // Quartz measures from the top-left of the main screen; AppKit from the bottom-left.
            return (r.minX, r.maxX, primary.frame.height - r.minY)
        }
        return nil
    }

    /// While the control panel is open, one pumpkin always sits on top of it,
    /// whatever the "Sit on windows" setting. It follows the panel when you drag it.
    func updatePanelSitter() {
        guard let p = pumpkins.first(where: { $0.isPanelSitter }) else { return }
        guard let w = panel, w.isVisible, !w.isMiniaturized else { p.targetAlpha = 0; return }
        let target = CGPoint(x: w.frame.minX + 70 * Pumpkin.scale, y: w.frame.maxY)
        p.targetAlpha = 1
        if p.alpha < 0.05 {
            // appear: drop in from a little above
            p.x = target.x; p.y = target.y + 40
            p.hop(to: target)
        } else if p.hopT >= 1 {
            if hypot(target.x - p.x, target.y - p.y) > 14 { p.hop(to: target) }
            else { p.x = target.x; p.y = target.y }
        } else if hypot(target.x - p.hopTo.x, target.y - p.hopTo.y) > 14 {
            p.hop(to: target)
        }
    }

    func updatePerch() {
        let perchers = pumpkins.filter { $0.isPercher }
        let active = opt.perch ? opt.sitters : 0
        guard active > 0, let f = frontWindowTop() else { perchers.forEach { $0.targetAlpha = 0 }; return }
        let probe = CGPoint(x: f.maxX - 80, y: f.top - 4)
        let screen = NSScreen.screens.first { $0.frame.contains(probe) }
        let roomy = screen.map { f.top + 50 < $0.visibleFrame.maxY } ?? false
        guard roomy else { perchers.forEach { $0.targetAlpha = 0 }; return }

        for (i, p) in perchers.enumerated() {
            guard i < active else { p.targetAlpha = 0; continue }
            let target = CGPoint(x: f.maxX - 60 - CGFloat(i) * 56 * Pumpkin.scale, y: f.top)
            if p.alpha < 0.05 {
                // appear: drop in from a little above
                p.x = target.x; p.y = target.y + 40
                p.hop(to: target)
                p.targetAlpha = 1
                if tracking { stats.hops += 1 }
                logEvent("hop")
            } else {
                p.targetAlpha = 1
                let d = hypot(target.x - p.hopTo.x, target.y - p.hopTo.y)
                if p.hopT >= 1 {
                    if hypot(target.x - p.x, target.y - p.y) > 14 {
                        p.hop(to: target)
                        if tracking { stats.hops += 1 }
                        logEvent("hop")
                    } else { p.x = target.x; p.y = target.y }
                } else if d > 14 {
                    p.hop(to: target)
                }
            }
        }
    }

    // MARK: drawing

    func drawPumpkin(_ c: CGContext, _ p: Pumpkin, t: Double, glow: CGFloat) {
        let s = p.size, h = p.height
        let cy = h * 0.5
        let fl = flicker(t, p.phase)

        c.saveGState()
        c.setAlpha(p.alpha)
        c.translateBy(x: p.x, y: p.y)

        // shadow
        c.setFillColor(color(0, 0, 0, 0.22))
        c.fillEllipse(in: CGRect(x: -s * 0.45, y: -s * 0.06, width: s * 0.9, height: s * 0.13))

        c.rotate(by: p.wobble)

        // candle glow around the pumpkin
        if glow > 0.01 {
            radial(c, at: CGPoint(x: 0, y: cy), radius: s * (0.8 + 0.5 * glow),
                   inner: [1, 0.62, 0.15, 0.5 * glow * fl], outer: [1, 0.5, 0.1, 0])
        }

        // stem and a curly vine
        c.setLineCap(.round)
        c.setStrokeColor(color(0.33, 0.27, 0.10))
        c.setLineWidth(s * 0.09)
        c.move(to: CGPoint(x: 0, y: h * 0.86))
        c.addQuadCurve(to: CGPoint(x: s * (0.05 + p.stemTilt), y: h * 1.13), control: CGPoint(x: -s * 0.01, y: h * 1.02))
        c.strokePath()
        c.setStrokeColor(color(0.30, 0.52, 0.18))
        c.setLineWidth(s * 0.022)
        c.move(to: CGPoint(x: s * 0.02, y: h * 0.96))
        c.addCurve(to: CGPoint(x: s * 0.22, y: h * 1.04), control1: CGPoint(x: s * 0.12, y: h * 1.12), control2: CGPoint(x: s * 0.26, y: h * 1.15))
        c.addCurve(to: CGPoint(x: s * 0.16, y: h * 0.98), control1: CGPoint(x: s * 0.20, y: h * 0.97), control2: CGPoint(x: s * 0.15, y: h * 0.96))
        c.strokePath()

        // body: five overlapping ribs
        let hue = 0.065 + p.tint * 0.03
        let ribs: [(CGFloat, CGFloat, CGFloat)] = [(-0.27, 0.50, 0.78), (0.27, 0.50, 0.78), (-0.14, 0.56, 0.87), (0.14, 0.56, 0.87), (0, 0.50, 0.96)]
        let body = CGMutablePath()
        for (off, w, bright) in ribs {
            let r = CGRect(x: off * s - w * s / 2, y: 0, width: w * s, height: h)
            body.addEllipse(in: r)
            c.setFillColor(NSColor(calibratedHue: hue, saturation: 0.92, brightness: bright, alpha: 1).cgColor)
            c.fillEllipse(in: r)
            c.setStrokeColor(NSColor(calibratedHue: hue - 0.01, saturation: 0.95, brightness: bright * 0.72, alpha: 0.8).cgColor)
            c.setLineWidth(max(1, s * 0.012))
            c.strokeEllipse(in: r)
        }
        // soft shading and a highlight
        c.saveGState()
        c.addPath(body); c.clip()
        if let g = CGGradient(colorSpace: rgb, colorComponents: [0.25, 0.05, 0, 0.30, 0.25, 0.05, 0, 0], locations: [0, 1], count: 2) {
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h * 0.6), options: [])
        }
        c.setFillColor(color(1, 1, 1, 0.16))
        c.fillEllipse(in: CGRect(x: -s * 0.30, y: h * 0.62, width: s * 0.16, height: h * 0.22))
        c.restoreGState()

        // blush, for the cute ones
        if p.restFace == .cute || p.restFace == .happy || p.restFace == .sleepy {
            c.setFillColor(color(1, 0.45, 0.55, 0.35))
            c.fillEllipse(in: CGRect(x: -s * 0.31, y: cy - s * 0.08, width: s * 0.11, height: s * 0.06))
            c.fillEllipse(in: CGRect(x: s * 0.20, y: cy - s * 0.08, width: s * 0.11, height: s * 0.06))
        }

        // the carved face, lit from inside
        let face = facePath(p.face, s: s, cy: cy)
        c.saveGState()
        c.addPath(face); c.clip()
        c.setFillColor(color(0.30, 0.08, 0))
        c.fill(CGRect(x: -s, y: -s, width: 2 * s, height: 3 * s))
        radial(c, at: CGPoint(x: 0, y: cy), radius: s * 0.55,
               inner: [1, 0.96, 0.62, fl], outer: [1, 0.55, 0.05, fl * 0.9])
        c.restoreGState()

        // uncarved bits: teeth and eye sparkles
        let skin = NSColor(calibratedHue: hue, saturation: 0.92, brightness: 0.93, alpha: 1).cgColor
        c.setFillColor(skin)
        if p.face == .toothy {
            let my = cy - s * 0.08
            c.fill(CGRect(x: -s * 0.125, y: my - s * 0.10, width: s * 0.07, height: s * 0.065))
            c.fill(CGRect(x: s * 0.055, y: my - s * 0.10, width: s * 0.07, height: s * 0.065))
        }
        if p.face == .cute {
            for ex in [-s * 0.14, s * 0.14] {
                c.fillEllipse(in: CGRect(x: ex + s * 0.008, y: cy + s * 0.075, width: s * 0.036, height: s * 0.036))
            }
        }

        // sleepy ones snore
        if p.face == .sleepy {
            let k = (t * 0.6 + p.phase).truncatingRemainder(dividingBy: 1)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: s * (0.16 + 0.08 * CGFloat(k)), weight: .heavy),
                .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.85 * (1 - CGFloat(k))),
            ]
            ("z" as NSString).draw(at: CGPoint(x: s * (0.28 + 0.12 * CGFloat(k)), y: h * (0.95 + 0.35 * CGFloat(k))), withAttributes: attrs)
        }
        c.restoreGState()
    }

    func facePath(_ f: Face, s: CGFloat, cy: CGFloat) -> CGPath {
        let p = CGMutablePath()
        switch f {
        case .cute:
            for ex in [-s * 0.14, s * 0.14] {
                p.addEllipse(in: CGRect(x: ex - s * 0.06, y: cy + s * 0.0, width: s * 0.12, height: s * 0.12))
            }
            crescent(p, cx: 0, y: cy - s * 0.08, w: s * 0.17, outer: s * 0.07, inner: s * 0.025, down: true)
        case .happy:
            for ex in [-s * 0.15, s * 0.15] {
                crescent(p, cx: ex, y: cy + s * 0.05, w: s * 0.14, outer: s * 0.07, inner: s * 0.03, down: false)
            }
            crescent(p, cx: 0, y: cy - s * 0.05, w: s * 0.36, outer: s * 0.16, inner: 0, down: true)
        case .sleepy:
            for ex in [-s * 0.15, s * 0.15] {
                crescent(p, cx: ex, y: cy + s * 0.06, w: s * 0.13, outer: s * 0.04, inner: s * 0.014, down: true)
            }
            p.addEllipse(in: CGRect(x: s * 0.0, y: cy - s * 0.15, width: s * 0.07, height: s * 0.07))
        case .surprised:
            for ex in [-s * 0.15, s * 0.15] {
                p.addEllipse(in: CGRect(x: ex - s * 0.075, y: cy - s * 0.005, width: s * 0.15, height: s * 0.15))
            }
            p.addEllipse(in: CGRect(x: -s * 0.055, y: cy - s * 0.20, width: s * 0.11, height: s * 0.13))
        case .classic:
            for ex in [-s * 0.17, s * 0.17] {
                polygon(p, [CGPoint(x: ex - s * 0.08, y: cy + s * 0.03), CGPoint(x: ex + s * 0.08, y: cy + s * 0.03),
                            CGPoint(x: ex, y: cy + s * 0.17)])
            }
            polygon(p, [CGPoint(x: -s * 0.035, y: cy - s * 0.04), CGPoint(x: s * 0.035, y: cy - s * 0.04), CGPoint(x: 0, y: cy + s * 0.02)])
            let w = s * 0.5, my = cy - s * 0.09
            var pts: [CGPoint] = []
            for i in 0...10 {
                let k = CGFloat(i) / 10
                pts.append(CGPoint(x: -w / 2 + w * k, y: my - s * 0.16 * sin(.pi * k)))
            }
            for i in stride(from: 10, through: 0, by: -1) {
                let k = CGFloat(i) / 10
                let tooth: CGFloat = (i % 2 == 1 && i >= 3 && i <= 7) ? s * 0.045 : 0
                pts.append(CGPoint(x: -w / 2 + w * k, y: my - s * 0.04 * sin(.pi * k) - tooth))
            }
            polygon(p, pts)
        case .toothy:
            polygon(p, [CGPoint(x: -s * 0.28, y: cy + s * 0.13), CGPoint(x: -s * 0.07, y: cy + s * 0.05), CGPoint(x: -s * 0.19, y: cy - s * 0.02)])
            polygon(p, [CGPoint(x: s * 0.28, y: cy + s * 0.13), CGPoint(x: s * 0.07, y: cy + s * 0.05), CGPoint(x: s * 0.19, y: cy - s * 0.02)])
            crescent(p, cx: 0, y: cy - s * 0.08, w: s * 0.56, outer: s * 0.2, inner: s * 0.05, down: true)
        }
        return p
    }

    func drawBat(_ c: CGContext, _ b: Bat, t: Double) {
        let s = b.size
        let f = CGFloat(sin(t * 14 + b.phase))
        c.saveGState()
        c.translateBy(x: b.x, y: b.y)
        c.setFillColor(color(0.13, 0.07, 0.18, 0.95))
        let wing = CGMutablePath()
        for side in [-1.0, 1.0] as [CGFloat] {
            let pts: [(CGFloat, CGFloat)] = [
                (0.08, 0.06), (0.5, 0.22 + 0.3 * f), (1.0, 0.10 + 0.6 * f), (0.8, -0.10 + 0.45 * f),
                (0.62, 0.0 + 0.3 * f), (0.45, -0.12 + 0.25 * f), (0.30, -0.02 + 0.12 * f), (0.08, -0.06),
            ]
            polygon(wing, pts.map { CGPoint(x: side * $0.0 * s, y: $0.1 * s) })
        }
        c.addPath(wing); c.fillPath()
        c.fillEllipse(in: CGRect(x: -s * 0.11, y: -s * 0.18, width: s * 0.22, height: s * 0.32))
        c.fillEllipse(in: CGRect(x: -s * 0.11, y: s * 0.04, width: s * 0.22, height: s * 0.2))
        let ears = CGMutablePath()
        polygon(ears, [CGPoint(x: -s * 0.10, y: s * 0.18), CGPoint(x: -s * 0.02, y: s * 0.2), CGPoint(x: -s * 0.08, y: s * 0.32)])
        polygon(ears, [CGPoint(x: s * 0.10, y: s * 0.18), CGPoint(x: s * 0.02, y: s * 0.2), CGPoint(x: s * 0.08, y: s * 0.32)])
        c.addPath(ears); c.fillPath()
        c.setFillColor(color(1, 0.65, 0.1))
        c.fillEllipse(in: CGRect(x: -s * 0.065, y: s * 0.12, width: s * 0.04, height: s * 0.04))
        c.fillEllipse(in: CGRect(x: s * 0.025, y: s * 0.12, width: s * 0.04, height: s * 0.04))
        c.restoreGState()
    }

    func facePreview(_ mode: String) -> NSImage {
        NSImage(size: NSSize(width: 70, height: 54), flipped: false) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            let specs: [(CGFloat, Face)]
            switch mode {
            case "spooky": specs = [(35, .classic)]
            case "mixed": specs = [(21, .happy), (49, .toothy)]
            default: specs = [(35, .cute)]
            }
            let sz: CGFloat = mode == "mixed" ? 30 : 44
            for (x, f) in specs {
                let p = Pumpkin(x: x, y: 6, baseSize: sz, face: f, isPercher: false)
                p.fixedSize = sz
                self.drawPumpkin(c, p, t: 0, glow: 0.4)
            }
            return true
        }
    }

    // MARK: - Control panel

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🎃"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc func togglePanel() {
        if let p = panel, p.isMiniaturized { p.deminiaturize(nil); return }
        if let p = panel, p.isVisible { p.performClose(nil); return }
        if panel == nil {
            // An ordinary window: other apps' windows can go in front of it, and it can be
            // minimised to the Dock.
            let p = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            p.title = "Virtual Pumpkin Porch"
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.level = .normal
            p.delegate = self
            p.standardWindowButton(.zoomButton)?.isHidden = true   // close and minimise only
            p.miniwindowImage = NSApp.applicationIconImage          // the pumpkin icon in the Dock
            panel = p
            refreshPanel()
            p.center()
        } else {
            refreshPanel()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        panelOpenedAt = Date()
        if tracking { stats.panelOpens += 1 }
        logEvent("panel_open")
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        closePanelBookkeeping()
        if NSApp.activationPolicy() != .accessory { NSApp.setActivationPolicy(.accessory) }
    }

    /// Minimising: show the app's pumpkin icon in the Dock while the panel is down there.
    func windowWillMiniaturize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        NSApp.setActivationPolicy(.regular)
        logEvent("panel_minimize")
    }

    /// Back from the Dock: hide the Dock icon again and bring the panel forward.
    func windowDidDeminiaturize(_ notification: Notification) {
        guard let p = panel, (notification.object as? NSWindow) === p else { return }
        logEvent("panel_restore")
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true)
            p.makeKeyAndOrderFront(nil)
        }
    }

    /// Clicking the pumpkin icon in the Dock brings the panel back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let p = panel, p.isMiniaturized { p.deminiaturize(nil) } else { togglePanel() }
        return true
    }

    /// A small app menu for while the Dock icon is showing.
    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Virtual Pumpkin Porch", action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Virtual Pumpkin Porch", action: #selector(quit), keyEquivalent: "q"))
        appMenu.items.forEach { $0.target = self }
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }

    func closePanelBookkeeping() {
        guard let opened = panelOpenedAt else { return }
        let d = Date().timeIntervalSince(opened)
        panelOpenedAt = nil
        if tracking { stats.secondsPanelOpen += d }
        logEvent("panel_close", duration: d)
    }

    func refreshPanel() {
        guard let p = panel else { return }
        switch opt.theme {
        case "system": p.appearance = nil
        case "light": p.appearance = NSAppearance(named: .aqua)
        default: p.appearance = NSAppearance(named: .darkAqua)    // halloween, dark
        }
        let content = buildPanelContent()
        p.contentView = content
        p.setContentSize(content.fittingSize)
        updateStatsLabels()
    }

    func buildPanelContent() -> NSView {
        let halloween = opt.theme == "halloween"
        let accent = NSColor(calibratedRed: 1, green: 0.58, blue: 0.12, alpha: 1)

        func header(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = .boldSystemFont(ofSize: 13)
            if halloween { l.textColor = accent }
            return l
        }
        func row(_ title: String, _ controls: [NSView]) -> NSStackView {
            let l = NSTextField(labelWithString: title)
            l.widthAnchor.constraint(equalToConstant: 140).isActive = true
            let r = NSStackView(views: [l as NSView] + controls)
            r.orientation = .horizontal
            r.spacing = 8
            r.alignment = .centerY
            return r
        }
        func slider(_ v: Double, _ lo: Double, _ hi: Double, _ sel: Selector) -> NSSlider {
            let s = NSSlider(value: v, minValue: lo, maxValue: hi, target: self, action: sel)
            s.isContinuous = true
            s.widthAnchor.constraint(equalToConstant: 170).isActive = true
            if halloween { s.trackFillColor = accent }
            return s
        }
        func toggle(_ on: Bool, _ sel: Selector) -> NSSwitch {
            let s = NSSwitch()
            s.state = on ? .on : .off
            s.target = self
            s.action = sel
            return s
        }
        func segments(_ labels: [String], _ selected: Int, _ sel: Selector) -> NSSegmentedControl {
            let s = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: self, action: sel)
            s.selectedSegment = selected
            if halloween { s.selectedSegmentBezelColor = accent }
            return s
        }
        func button(_ title: String, _ sel: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: sel)
            b.bezelStyle = .rounded
            return b
        }
        func column(_ views: [NSView]) -> NSStackView {
            let s = NSStackView(views: views)
            s.orientation = .vertical
            s.alignment = .leading
            s.spacing = 9
            return s
        }

        // Faces, with little previews to click
        faceButtons = []
        for (i, mode) in ["cute", "spooky", "mixed"].enumerated() {
            let b = NSButton(title: mode.capitalized, image: facePreview(mode), target: self, action: #selector(pickFaces(_:)))
            b.tag = i
            b.setButtonType(.pushOnPushOff)
            b.bezelStyle = .regularSquare
            b.imagePosition = .imageAbove
            b.state = opt.faces == mode ? .on : .off
            b.widthAnchor.constraint(equalToConstant: 92).isActive = true
            b.heightAnchor.constraint(equalToConstant: 80).isActive = true
            faceButtons.append(b)
        }
        let faceRow = NSStackView(views: faceButtons)
        faceRow.spacing = 8

        let countSlider = slider(Double(opt.count), 1, 10, #selector(countChanged(_:)))
        countSlider.numberOfTickMarks = 10
        countSlider.allowsTickMarkValuesOnly = true
        let cl = NSTextField(labelWithString: "\(opt.count)")
        countLabel = cl

        let sitters = segments(["1", "2", "3"], opt.sitters - 1, #selector(sittersChanged(_:)))
        sitters.isEnabled = opt.perch
        sitterControl = sitters

        let batModes = ["off", "rare", "normal", "flock"]
        let themes = ["halloween", "system", "light", "dark"]

        let login = toggle(loginEnabled, #selector(loginChanged(_:)))
        login.isEnabled = loginAvailable

        let left = column([
            header("Pumpkins"),
            faceRow,
            row("How many (per screen)", [countSlider, cl]),
            row("Size", [slider(opt.size, 0.6, 1.6, #selector(sizeChanged(_:)))]),
            row("Candle glow", [slider(opt.glow, 0, 1, #selector(glowChanged(_:)))]),
            row("Sit on windows", [toggle(opt.perch, #selector(perchChanged(_:))), sitters]),
            row("Bats", [segments(["Off", "Rare", "Normal", "Flock"], batModes.firstIndex(of: opt.bats) ?? 2, #selector(batsChanged(_:)))]),
            row("Fright reaction", [segments(["Gentle wobble", "Big jump"], opt.fright == "big" ? 1 : 0, #selector(frightChanged(_:)))]),
            button("Rearrange the pumpkins", #selector(shuffle)),
            header("Behaviour"),
            row("Pause", [toggle(opt.paused, #selector(pauseChanged(_:)))]),
            row("Hide in full-screen apps", [toggle(opt.hideInFullscreen, #selector(fullscreenChanged(_:)))]),
            row("Start at login", [login]),
            row("Remember my choices", [toggle(settings.rememberChoices, #selector(rememberChanged(_:)))]),
            header("Look"),
            row("Panel theme", [segments(["Halloween", "System", "Light", "Dark"], themes.firstIndex(of: opt.theme) ?? 0, #selector(themeChanged(_:)))]),
        ])

        // Your data
        let info = NSTextField(wrappingLabelWithString: dataInfoText)
        info.font = .systemFont(ofSize: 11)
        info.textColor = .secondaryLabelColor
        info.preferredMaxLayoutWidth = 270
        info.widthAnchor.constraint(equalToConstant: 270).isActive = true

        statsLabels = (0..<8).map { _ -> NSTextField in
            let l = NSTextField(labelWithString: "")
            l.font = .systemFont(ofSize: 12)
            return l
        }

        let footer = NSStackView(views: [button("About Virtual Pumpkin Porch", #selector(showAbout)), button("Quit", #selector(quit))])
        footer.spacing = 8

        var rightViews: [NSView] = [
            header("Your data"),
            row("Data tracking", [toggle(tracking, #selector(trackingChanged(_:)))]),
            info,
            button("Open data folder", #selector(openDataFolder)),
            button("Export my data (CSV + JSON)…", #selector(exportData)),
            button("Delete my data…", #selector(deleteData)),
            header("Pumpkin stats"),
        ]
        rightViews += statsLabels as [NSView]
        rightViews.append(footer)
        let right = column(rightViews)

        let columns = NSStackView(views: [left, right])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = 28
        columns.translatesAutoresizingMaskIntoConstraints = false

        let root: NSView
        if halloween {
            root = NSView()
            root.wantsLayer = true
            root.layer?.backgroundColor = NSColor(calibratedRed: 0.13, green: 0.07, blue: 0.20, alpha: 1).cgColor
        } else {
            let v = NSVisualEffectView()
            v.material = .windowBackground
            v.state = .active
            root = v
        }
        root.addSubview(columns)
        NSLayoutConstraint.activate([
            columns.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            columns.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            columns.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            columns.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
        ])
        return root
    }

    func updateStatsLabels() {
        guard statsLabels.count == 8 else { return }
        let df = DateFormatter()
        df.dateStyle = .medium
        let changes = stats.settingChanges.values.reduce(0, +)
        let lines = [
            "Pumpkins on duty: \(duration(stats.secondsRunning))",
            "Pumpkins frightened: \(stats.frights)",
            "Bats: \(stats.bats) · Hops onto windows: \(stats.hops)",
            "Cute \(duration(stats.secondsCute)) · Spooky \(duration(stats.secondsSpooky)) · Mixed \(duration(stats.secondsMixed))",
            "Panel opened \(stats.panelOpens) times (\(duration(stats.secondsPanelOpen)))",
            "Settings changed \(changes) times",
            "Started \(stats.launches) times since \(df.string(from: stats.firstRun))",
            tracking ? "Version \(appVersion) · ID \(settings.installID.prefix(8))…"
                     : "Tracking is off, so these totals are paused.",
        ]
        for (l, s) in zip(statsLabels, lines) { l.stringValue = s }
    }

    // MARK: panel actions

    @objc func pickFaces(_ sender: NSButton) {
        let modes = ["cute", "spooky", "mixed"]
        let old = opt.faces
        opt.faces = modes[sender.tag]
        for b in faceButtons { b.state = b.tag == sender.tag ? .on : .off }
        if old != opt.faces { refaceAll() }
        record("faces", from: old, to: opt.faces)
    }

    @objc func countChanged(_ s: NSSlider) {
        let old = opt.count
        let new = Int(s.doubleValue.rounded())
        if new != old { opt.count = new; adjustCount() }
        countLabel?.stringValue = "\(new)"
        sliderChange("count", before: "\(old)", after: "\(new)")
    }

    @objc func sizeChanged(_ s: NSSlider) {
        let old = opt.size
        opt.size = s.doubleValue
        Pumpkin.scale = CGFloat(opt.size)
        redrawAll()
        sliderChange("size", before: fmt(old), after: fmt(opt.size))
    }

    @objc func glowChanged(_ s: NSSlider) {
        let old = opt.glow
        opt.glow = s.doubleValue
        redrawAll()
        sliderChange("glow", before: fmt(old), after: fmt(opt.glow))
    }

    @objc func perchChanged(_ s: NSSwitch) {
        let old = opt.perch
        opt.perch = s.state == .on
        sitterControl?.isEnabled = opt.perch
        record("sit_on_windows", from: "\(old)", to: "\(opt.perch)")
    }

    @objc func sittersChanged(_ s: NSSegmentedControl) {
        let old = opt.sitters
        opt.sitters = s.selectedSegment + 1
        record("sitters", from: "\(old)", to: "\(opt.sitters)")
    }

    @objc func batsChanged(_ s: NSSegmentedControl) {
        let modes = ["off", "rare", "normal", "flock"]
        let old = opt.bats
        opt.bats = modes[max(0, s.selectedSegment)]
        scheduleNextBat(from: now)
        record("bats", from: old, to: opt.bats)
    }

    @objc func frightChanged(_ s: NSSegmentedControl) {
        let old = opt.fright
        opt.fright = s.selectedSegment == 1 ? "big" : "gentle"
        record("fright", from: old, to: opt.fright)
    }

    @objc func pauseChanged(_ s: NSSwitch) {
        let old = opt.paused
        opt.paused = s.state == .on
        guard old != opt.paused else { return }
        if opt.paused {
            timer?.invalidate(); timer = nil
            windows.forEach { $0.orderOut(nil) }
            pausedAt = Date()
            logEvent("pause")
        } else {
            windows.forEach { $0.orderFrontRegardless() }
            startTimer()
            let d = pausedAt.map { Date().timeIntervalSince($0) } ?? 0
            if tracking { stats.secondsPaused += d }
            pausedAt = nil
            logEvent("resume", duration: d)
        }
        record("paused", from: "\(old)", to: "\(opt.paused)")
    }

    @objc func fullscreenChanged(_ s: NSSwitch) {
        let old = opt.hideInFullscreen
        opt.hideInFullscreen = s.state == .on
        applyFullscreenBehaviour()
        record("hide_in_fullscreen", from: "\(old)", to: "\(opt.hideInFullscreen)")
    }

    @objc func loginChanged(_ s: NSSwitch) {
        let old = loginEnabled
        setLogin(s.state == .on)
        let new = loginEnabled
        s.state = new ? .on : .off
        record("start_at_login", from: "\(old)", to: "\(new)")
    }

    @objc func rememberChanged(_ s: NSSwitch) {
        let old = settings.rememberChoices
        settings.rememberChoices = s.state == .on
        record("remember_choices", from: "\(old)", to: "\(settings.rememberChoices)")
    }

    @objc func themeChanged(_ s: NSSegmentedControl) {
        let themes = ["halloween", "system", "light", "dark"]
        let old = opt.theme
        opt.theme = themes[max(0, s.selectedSegment)]
        record("panel_theme", from: old, to: opt.theme)
        DispatchQueue.main.async { self.refreshPanel() }
    }

    @objc func trackingChanged(_ s: NSSwitch) {
        setTracking(s.state == .on)
        updateStatsLabels()
    }

    @objc func shuffle() {
        buildPumpkins()
        if tracking { stats.settingChanges["rearrange", default: 0] += 1 }
        logEvent("setting_changed", setting: "rearrange", value: "pressed")
    }

    @objc func showAbout() {
        alert("🎃 Virtual Pumpkin Porch \(appVersion)", """
        Candle-lit pumpkins that sit above your Dock and hop onto your windows.

        Inspired by Fall Desktop for Windows by starrlord (github.com/starrlord/FallDesktop). \
        Virtual Pumpkin Porch is a separate, original Mac app and shares no code with it.

        Your data: tracking is optional and \(tracking ? "currently ON" : "currently OFF"). \
        Everything recorded stays on this Mac and is never sent anywhere. See "Your data" in this panel.

        Free and open source under the MIT License. Provided "as is", without warranty of any kind.
        """)
    }

    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - Main

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)   // no Dock icon, just the menu bar pumpkin
app.run()
