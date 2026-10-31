// Pumpkin Porch: carved pumpkins that sit on your Mac.
//
// A row of candle-lit pumpkins sits on a "porch" just above the Dock, and a
// couple of little ones hop onto the top edge of whatever window is in front.
// Point at a pumpkin and it gets a fright. Now and then a bat flaps past.
// Clicks always pass straight through to whatever is underneath.
//
// Inspired by Fall Desktop for Windows (github.com/starrlord/FallDesktop);
// this is a separate, original Mac app and shares no code with it.
// Local-only stats: nothing is ever sent anywhere.
// MIT License, see LICENSE.
//
// Build:  ./build.sh        (or: swiftc -O PumpkinPorch.swift -o PumpkinPorch)
// Control it from the pumpkin in the menu bar.

import AppKit

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

// MARK: - Model

enum Face { case cute, happy, sleepy, classic, toothy, surprised }

final class Pumpkin {
    var x: CGFloat              // centre, global screen coordinates
    var y: CGFloat              // bottom
    let size: CGFloat           // width
    var restFace: Face
    var face: Face
    let tint: CGFloat
    let phase: Double
    let stemTilt: CGFloat
    let isPercher: Bool

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

    init(x: CGFloat, y: CGFloat, size: CGFloat, face: Face, isPercher: Bool) {
        self.x = x; self.y = y; self.size = size
        self.restFace = face; self.face = face
        self.tint = rnd(0, 1)
        self.phase = rndD(0, 100)
        self.stemTilt = rnd(-0.06, 0.06)
        self.isPercher = isPercher
    }

    var height: CGFloat { size * 0.78 }

    /// Everything we might paint, including the glow, stem, wobble and "z"s.
    var bounds: CGRect {
        let m = size * 0.65
        return CGRect(x: x - size / 2 - m, y: y - size * 0.2, width: size + 2 * m, height: height + size * 0.2 + m + size * 0.35)
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

    init(screen: CGRect) {
        let dir: CGFloat = Bool.random() ? 1 : -1
        size = rnd(20, 32)
        x = dir > 0 ? screen.minX - 60 : screen.maxX + 60
        baseY = screen.minY + screen.height * rnd(0.45, 0.85)
        y = baseY
        vx = dir * rnd(150, 230)
        phase = rndD(0, 100)
        minX = screen.minX - 90
        maxX = screen.maxX + 90
    }

    var bounds: CGRect { CGRect(x: x - size * 1.15, y: y - size * 0.9, width: size * 2.3, height: size * 1.9) }
    var gone: Bool { x < minX || x > maxX }
}

// MARK: - Local stats (kept on this Mac only, never sent anywhere)

struct Stats: Codable {
    var firstRun = Date()
    var launches = 0
    var secondsRunning: Double = 0
    var secondsCute: Double = 0
    var secondsSpooky: Double = 0
    var frights = 0
    var bats = 0
    var hops = 0
}

enum StatsStore {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Pumpkin Porch", isDirectory: true)
    }
    static var file: URL { folder.appendingPathComponent("stats.json") }

    static func load() -> Stats {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: file), let s = try? dec.decode(Stats.self, from: data) else { return Stats() }
        return s
    }

    static func save(_ s: Stats) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(s) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

func duration(_ secs: Double) -> String {
    let m = Int(secs / 60)
    if m < 60 { return "\(m) min" }
    return "\(m / 60) h \(m % 60) min"
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
        c.saveGState()
        c.translateBy(x: -o.x, y: -o.y)
        for p in ctl.pumpkins where p.alpha > 0.01 && p.bounds.intersects(globalDirty) {
            ctl.drawPumpkin(c, p)
        }
        for b in ctl.bats where b.bounds.intersects(globalDirty) {
            ctl.drawBat(c, b)
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
    w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    w.isReleasedWhenClosed = false
    let v = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
    v.controller = controller
    w.contentView = v
    return w
}

// MARK: - App

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var windows: [NSWindow] = []
    var pumpkins: [Pumpkin] = []
    var bats: [Bat] = []
    var timer: Timer?
    var statusItem: NSStatusItem!

    // settings
    var paused = false
    var spooky = false
    var perch = true
    var batsOn = true
    var porchCount = 4

    var start = Date()
    var lastTick: Double = 0
    var lastPerchCheck: Double = -1
    var nextBat: Double = 4
    var lastPerchTarget: CGPoint?
    var stats = StatsStore.load()
    var lastSave: Double = 0

    var now: Double { Date().timeIntervalSince(start) }

    func applicationDidFinishLaunching(_ note: Notification) {
        stats.launches += 1
        StatsStore.save(stats)
        buildMenu()
        rebuildWindows()
        buildPumpkins()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        startTimer()
    }

    // MARK: setup

    func rebuildWindows() {
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows = NSScreen.screens.map { makeOverlay(for: $0, controller: self) }
        if !paused { windows.forEach { $0.orderFrontRegardless() } }
    }

    func faces() -> [Face] { spooky ? [.classic, .toothy, .classic, .happy] : [.cute, .happy, .sleepy, .cute] }

    func buildPumpkins() {
        let perchers = pumpkins.filter { $0.isPercher }
        pumpkins = []
        for screen in NSScreen.screens {
            let vf = screen.visibleFrame
            var placed: [(CGFloat, CGFloat)] = []
            var tries = 0
            while placed.count < porchCount && tries < 300 {
                tries += 1
                let size = rnd(44, 72)
                let x = rnd(vf.minX + 50, vf.maxX - 50)
                if placed.contains(where: { abs($0.0 - x) < ($0.1 + size) / 2 + 14 }) { continue }
                placed.append((x, size))
                pumpkins.append(Pumpkin(x: x, y: vf.minY + 2, size: size, face: faces().randomElement()!, isPercher: false))
            }
        }
        if perchers.isEmpty {
            for s in [40, 32] as [CGFloat] {
                let p = Pumpkin(x: -1000, y: -1000, size: s, face: faces().randomElement()!, isPercher: true)
                p.alpha = 0; p.targetAlpha = 0
                pumpkins.append(p)
            }
        } else {
            pumpkins.append(contentsOf: perchers)
        }
        lastPerchTarget = nil
        redrawAll()
    }

    func refaceAll() {
        for p in pumpkins { p.restFace = faces().randomElement()!; p.face = p.restFace }
        redrawAll()
    }

    // MARK: menu

    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🎃"
        statusItem.menu = makeMenu()
    }

    func applicationWillTerminate(_ note: Notification) { StatsStore.save(stats) }

    func makeMenu() -> NSMenu {
        let m = NSMenu()
        m.delegate = self
        fillMenu(m)
        return m
    }

    // Rebuilt every time the menu opens, so the stats are always current.
    func menuNeedsUpdate(_ menu: NSMenu) { fillMenu(menu) }

    func info(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    func statsMenu() -> NSMenuItem {
        let sub = NSMenu()
        let df = DateFormatter()
        df.dateStyle = .medium
        sub.addItem(info("Pumpkins on duty: \(duration(stats.secondsRunning))"))
        sub.addItem(info("Pumpkins frightened: \(stats.frights)"))
        sub.addItem(info("Bats flown past: \(stats.bats)"))
        sub.addItem(info("Hops onto windows: \(stats.hops)"))
        sub.addItem(info("Cute faces: \(duration(stats.secondsCute)) · Spooky faces: \(duration(stats.secondsSpooky))"))
        sub.addItem(info("Started \(stats.launches) times since \(df.string(from: stats.firstRun))"))
        sub.addItem(.separator())
        sub.addItem(info("🔒 Your stats stay on this Mac."))
        sub.addItem(info("Nothing is ever sent anywhere."))
        sub.addItem(item("Show stats file in Finder", #selector(showStatsFile), on: false))
        sub.addItem(item("Reset stats", #selector(resetStats), on: false))
        let it = NSMenuItem(title: "Pumpkin stats", action: nil, keyEquivalent: "")
        it.submenu = sub
        return it
    }

    @objc func showAbout() {
        let a = NSAlert()
        a.messageText = "🎃 Pumpkin Porch 1.0"
        a.informativeText = """
        Candle-lit pumpkins that sit above your Dock and hop onto your windows.

        Inspired by Fall Desktop for Windows by starrlord (github.com/starrlord/FallDesktop). \
        Pumpkin Porch is a separate, original Mac app and shares no code with it.

        Your privacy: Pumpkin Porch keeps a few fun stats (time running, frights, bats, hops) \
        in a small file on this Mac only. Nothing is ever sent anywhere, and the app never \
        records which apps or windows you use. Open the file from Pumpkin stats › Show stats file in Finder.

        Free and open source under the MIT License. Provided "as is", without warranty of any kind.
        """
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    @objc func showStatsFile() {
        StatsStore.save(stats)
        NSWorkspace.shared.activateFileViewerSelecting([StatsStore.file])
    }

    @objc func resetStats() {
        stats = Stats()
        StatsStore.save(stats)
    }

    func fillMenu(_ m: NSMenu) {
        m.removeAllItems()
        m.addItem(item("Pause", #selector(togglePause), on: paused))
        m.addItem(.separator())
        m.addItem(item("Cute faces", #selector(setCute), on: !spooky))
        m.addItem(item("Spooky faces", #selector(setSpooky), on: spooky))
        m.addItem(.separator())
        for (title, n) in [("A few pumpkins", 2), ("Some pumpkins", 4), ("Lots of pumpkins", 7)] {
            let it = item(title, #selector(setCount(_:)), on: porchCount == n)
            it.tag = n
            m.addItem(it)
        }
        m.addItem(item("Sit on top of windows", #selector(togglePerch), on: perch))
        m.addItem(item("Bats", #selector(toggleBats), on: batsOn))
        m.addItem(item("Rearrange the pumpkins", #selector(shuffle), on: false))
        m.addItem(.separator())
        m.addItem(statsMenu())
        m.addItem(item("About Pumpkin Porch…", #selector(showAbout), on: false))
        m.addItem(.separator())
        m.addItem(item("Quit Pumpkin Porch", #selector(quit), on: false))
    }

    func item(_ title: String, _ sel: Selector, on: Bool) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        it.state = on ? .on : .off
        return it
    }

    func refreshMenu() { statusItem.menu = makeMenu() }

    @objc func togglePause() {
        paused.toggle()
        if paused { timer?.invalidate(); timer = nil; windows.forEach { $0.orderOut(nil) } }
        else { windows.forEach { $0.orderFrontRegardless() }; startTimer() }
        refreshMenu()
    }
    @objc func setCute() { spooky = false; refaceAll(); refreshMenu() }
    @objc func setSpooky() { spooky = true; refaceAll(); refreshMenu() }
    @objc func setCount(_ sender: NSMenuItem) { porchCount = sender.tag; buildPumpkins(); refreshMenu() }
    @objc func togglePerch() {
        perch.toggle()
        if !perch { for p in pumpkins where p.isPercher { p.targetAlpha = 0 } }
        lastPerchTarget = nil
        refreshMenu()
    }
    @objc func toggleBats() { batsOn.toggle(); if !batsOn { bats.removeAll(); redrawAll() }; refreshMenu() }
    @objc func shuffle() { buildPumpkins() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func screensChanged() { rebuildWindows(); buildPumpkins() }

    // MARK: animation

    func startTimer() {
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

    @objc func tick() {
        let t = now
        let dt = CGFloat(min(0.1, t - lastTick))
        lastTick = t
        let mouse = NSEvent.mouseLocation

        stats.secondsRunning += Double(dt)
        if spooky { stats.secondsSpooky += Double(dt) } else { stats.secondsCute += Double(dt) }
        if t - lastSave > 30 { lastSave = t; StatsStore.save(stats) }

        if perch && t - lastPerchCheck > 0.1 { lastPerchCheck = t; updatePerch() }

        for p in pumpkins {
            let before = p.bounds
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
                stats.frights += 1
                p.face = .surprised
                p.surprisedUntil = t + 1.6
                p.wobbleVel += (Bool.random() ? 1 : -1) * rnd(3.5, 5)
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
            if p.alpha > 0.01 || p.targetAlpha > 0 { invalidate(before.union(p.bounds)) }
        }

        if batsOn && t > nextBat, let screen = NSScreen.screens.randomElement() {
            bats.append(Bat(screen: screen.frame))
            stats.bats += 1
            nextBat = t + rndD(18, 45)
        }
        for b in bats {
            let before = b.bounds
            b.x += b.vx * dt
            b.y = b.baseY + CGFloat(sin(t * 1.7 + b.phase)) * 22
            invalidate(before.union(b.bounds))
        }
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

    func updatePerch() {
        let perchers = pumpkins.filter { $0.isPercher }
        guard let f = frontWindowTop() else { perchers.forEach { $0.targetAlpha = 0 }; return }
        let probe = CGPoint(x: f.maxX - 80, y: f.top - 4)
        let screen = NSScreen.screens.first { $0.frame.contains(probe) }
        let roomy = screen.map { f.top + 50 < $0.visibleFrame.maxY } ?? false
        guard roomy else { perchers.forEach { $0.targetAlpha = 0 }; lastPerchTarget = nil; return }

        let anchor = CGPoint(x: f.maxX, y: f.top)
        for (i, p) in perchers.enumerated() {
            let target = CGPoint(x: f.maxX - 60 - CGFloat(i) * 56, y: f.top)
            if p.alpha < 0.05 {
                // appear: drop in from a little above
                p.x = target.x; p.y = target.y + 40
                p.hop(to: target)
                p.targetAlpha = 1
                stats.hops += 1
            } else {
                p.targetAlpha = 1
                let d = hypot(target.x - p.hopTo.x, target.y - p.hopTo.y)
                if p.hopT >= 1 {
                    if hypot(target.x - p.x, target.y - p.y) > 14 { p.hop(to: target); stats.hops += 1 }
                    else { p.x = target.x; p.y = target.y }
                } else if d > 14 {
                    p.hop(to: target)
                }
            }
        }
        lastPerchTarget = anchor
    }

    // MARK: drawing

    func drawPumpkin(_ c: CGContext, _ p: Pumpkin) {
        let t = now
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
        radial(c, at: CGPoint(x: 0, y: cy), radius: s * 1.05,
               inner: [1, 0.62, 0.15, 0.30 * fl], outer: [1, 0.5, 0.1, 0])

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
        let cuteFace = p.restFace == .cute || p.restFace == .happy || p.restFace == .sleepy
        if !spooky && cuteFace {
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
        if p.face == .sleepy && !spooky {
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

    func drawBat(_ c: CGContext, _ b: Bat) {
        let t = now
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
}

// MARK: - Main

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)   // no Dock icon, just the menu bar pumpkin
app.run()
