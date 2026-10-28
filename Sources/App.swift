// Backseat menu-bar app: asks before an AI agent drives the Mac, and shows the user while it does.
import AppKit
import QuartzCore

let accent = NSColor.systemOrange

func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor? = nil) -> NSImage? {
    var config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
    if let color { config = config.applying(.init(paletteColors: [color])) }
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
}

/// Menu-bar icon, sized like the system's own status items.
func statusIcon(filled: Bool, color: NSColor? = nil) -> NSImage? {
    let name = filled ? "inset.filled.square.dashed.micro" : "inset.square.dashed.micro"
    let image = symbol(name, size: 16, weight: .regular, color: color)
    image?.isTemplate = color == nil
    return image
}

/// Rounded mask for NSVisualEffectView (the documented way to round a vibrancy view).
func roundedMask(radius: CGFloat) -> NSImage {
    let edge = radius * 2 + 1
    let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        return true
    }
    image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
}

func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = font
    field.textColor = color
    field.lineBreakMode = .byTruncatingTail
    return field
}

/// Pill button drawn by hand: system buttons only show their accent colour in a key window, and this panel
/// never becomes key. Reacts to the first click without focusing the app.
final class PillButton: NSButton {
    private let fill: NSColor

    init(title: String, fill: NSColor, textColor: NSColor, target: AnyObject, action: Selector) {
        self.fill = fill
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = fill.cgColor
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: textColor, .font: NSFont.systemFont(ofSize: 13, weight: .medium)])
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: attributedTitle.size().width + 28).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = fill.blended(withFraction: 0.25, of: .black)?.cgColor
        super.mouseDown(with: event)
        layer?.backgroundColor = fill.cgColor
    }
}

/// Frosted HUD panel under the menu bar, on every Space.
final class Banner: NSPanel {
    var onAllow: (() -> Void)?
    var onDeny: (() -> Void)?

    private let radius: CGFloat = 18
    private let effect = NSVisualEffectView()
    private let border = NSView()
    private let headline = label("", font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
    private let detailLabel = label("", font: .systemFont(ofSize: 11.5), color: .secondaryLabelColor)
    private let timerLabel = label("0:00", font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium), color: .secondaryLabelColor)
    private let dot = NSView()
    private let ringHost = NSView()
    private let track = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let clock = NSStackView()
    private let buttons = NSStackView()
    private let stack = NSStackView()
    private(set) var isShown = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 60),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = roundedMask(radius: radius)

        // hairline edge like system panels
        border.wantsLayer = true
        border.layer?.cornerRadius = radius
        border.layer?.borderWidth = 0.5
        border.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        // orange badge with a white hand, inside a countdown ring
        let badge = NSView(frame: NSRect(x: 4, y: 4, width: 30, height: 30))
        badge.wantsLayer = true
        badge.layer?.backgroundColor = accent.cgColor
        badge.layer?.cornerRadius = 15
        let hand = NSImageView(image: symbol("hand.raised.fill", size: 14, color: .white) ?? NSImage())
        hand.frame = badge.bounds
        badge.addSubview(hand)
        ringHost.wantsLayer = true
        ringHost.addSubview(badge)
        ringHost.translatesAutoresizingMaskIntoConstraints = false
        ringHost.widthAnchor.constraint(equalToConstant: 38).isActive = true
        ringHost.heightAnchor.constraint(equalToConstant: 38).isActive = true
        // circle starting at 12 o'clock, drawn clockwise, so draining strokeEnd runs counter-clockwise like a timer
        let circle = CGMutablePath()
        circle.addArc(center: CGPoint(x: 19, y: 19), radius: 17.5, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        for layer in [track, ring] {
            layer.path = circle
            layer.fillColor = nil
            layer.lineWidth = 2.5
            layer.frame = CGRect(x: 0, y: 0, width: 38, height: 38)
        }
        track.strokeColor = accent.withAlphaComponent(0.22).cgColor
        ring.strokeColor = accent.cgColor
        ring.lineCap = .round
        ringHost.layer?.addSublayer(track)
        ringHost.layer?.addSublayer(ring)

        let texts = NSStackView(views: [headline, detailLabel])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 1
        detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 380).isActive = true
        for field in [headline, detailLabel] {
            field.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        }

        // active: pulsing "recording" dot + elapsed time
        dot.wantsLayer = true
        dot.layer?.backgroundColor = accent.cgColor
        dot.layer?.cornerRadius = 3.5
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 7).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 7).isActive = true
        clock.setViews([dot, timerLabel], in: .leading)
        clock.spacing = 5

        // pending: Not Now / Allow
        let deny = PillButton(title: "Not Now", fill: NSColor.white.withAlphaComponent(0.14), textColor: .labelColor,
                              target: self, action: #selector(denyClicked))
        let allow = PillButton(title: "Allow", fill: accent, textColor: .white, target: self, action: #selector(allowClicked))
        buttons.setViews([deny, allow], in: .leading)
        buttons.spacing = 8

        stack.setViews([ringHost, texts, clock, buttons], in: .leading)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.setCustomSpacing(18, after: texts)
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 14)

        let root = NSView()
        root.addSubview(effect)
        effect.addSubview(stack)
        root.addSubview(border)
        contentView = root
    }

    @objc private func allowClicked() { onAllow?() }
    @objc private func denyClicked() { onDeny?() }

    /// Ask for permission; the ring drains over `seconds`.
    func showRequest(agent: String, reason: String, seconds: Double) {
        headline.stringValue = "\(agent) wants to use your Mac"
        updateCountdown(reason: reason, remaining: seconds)
        clock.isHidden = true
        buttons.isHidden = false
        ignoresMouseEvents = false
        track.isHidden = false
        ring.isHidden = false
        ring.removeAllAnimations()
        let drain = CABasicAnimation(keyPath: "strokeEnd")
        drain.fromValue = 1
        drain.toValue = 0
        drain.duration = seconds
        drain.fillMode = .forwards
        drain.isRemovedOnCompletion = false
        ring.add(drain, forKey: "drain")
        present()
    }

    func updateCountdown(reason: String, remaining: Double) {
        detailLabel.stringValue = "\(reason) · starting in \(Int(ceil(max(remaining, 0))))s"
    }

    /// Click-through "in control" state.
    func showActive(agent: String, reason: String, elapsed: TimeInterval) {
        headline.stringValue = "\(agent) is using your Mac"
        updateActive(reason: reason, elapsed: elapsed)
        clock.isHidden = false
        buttons.isHidden = true
        ignoresMouseEvents = true
        ring.removeAllAnimations()
        track.isHidden = true
        ring.isHidden = true
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 1.0
        breathe.toValue = 0.25
        breathe.duration = 0.9
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.layer?.add(breathe, forKey: "breathe")
        present()
    }

    func updateActive(reason: String, elapsed: TimeInterval) {
        detailLabel.stringValue = "Please don't use the mouse or keyboard · \(reason)"
        let secs = Int(max(elapsed, 0))
        timerLabel.stringValue = String(format: "%d:%02d", secs / 60, secs % 60)
    }

    private func present() {
        stack.layoutSubtreeIfNeeded()
        let size = NSSize(width: min(max(stack.fittingSize.width, 340), 680), height: 60)
        for view in [effect, border, stack] as [NSView] { view.frame = NSRect(origin: .zero, size: size) }
        guard let screen = NSScreen.main else { return }
        let final = NSRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 8,
                           width: size.width, height: size.height)
        if isShown {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                animator().setFrame(final, display: true)
            }
            invalidateShadow()
            return
        }
        isShown = true
        setFrame(final.offsetBy(dx: 0, dy: 10), display: false)
        alphaValue = 0
        orderFrontRegardless()
        invalidateShadow()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(final, display: true)
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isShown else { return }
        isShown = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            animator().alphaValue = 0
            animator().setFrame(frame.offsetBy(dx: 0, dy: 8), display: true)
        }, completionHandler: { [weak self] in
            guard let self, !self.isShown else { return }
            self.orderOut(nil)
        })
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let banner = Banner()
    private var current: SeatState?
    private var answered: Double?  // request id we already answered

    func applicationDidFinishLaunching(_ notification: Notification) {
        banner.onAllow = { [weak self] in self?.answer("allow") }
        banner.onDeny = { [weak self] in self?.answer("deny") }
        render(.idle)
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        let state = Seat.read()
        let now = Date().timeIntervalSince1970
        // an answered request stays "pending" on disk until the CLI writes the result; don't re-render it
        let stale = state.isPending && state.since == answered
        if !stale && (state.phase != current?.phase || state.reason != current?.reason || state.since != current?.since) {
            if state.isPending || (state.isActive && current?.isActive != true) {
                NSSound(named: "Tink")?.play()
            }
            render(state)
        }
        let reason = state.reason ?? "Working"
        if state.isPending, !stale, let since = state.since {
            let remaining = (state.countdown ?? 10) - (now - since)
            banner.updateCountdown(reason: reason, remaining: remaining)
            if remaining <= 0 { answer("allow") }
        } else if state.isActive {
            banner.updateActive(reason: reason, elapsed: now - (state.since ?? now))
        }
    }

    /// Reply to a pending request; the CLI waits for this file.
    private func answer(_ verdict: String) {
        guard let state = current, state.isPending, let id = state.since, answered != id else { return }
        answered = id
        Seat.respond(verdict, id: id)
        if verdict == "allow" {
            var active = state
            active.phase = "active"
            active.since = Date().timeIntervalSince1970
            render(active)  // shown right away; the CLI writes the real active state next
        } else {
            render(.idle)
        }
    }

    private func render(_ state: SeatState) {
        current = state
        let menu = NSMenu()
        guard let button = statusItem.button else { return }
        button.title = ""
        let reason = state.reason ?? "Working"
        let agent = state.agentName
        button.appearsDisabled = false
        if state.isPending {
            button.image = statusIcon(filled: true, color: accent.withAlphaComponent(0.55))
            button.toolTip = "\(agent) wants to use your Mac — \(reason)"
            let remaining = (state.countdown ?? 10) - (Date().timeIntervalSince1970 - (state.since ?? 0))
            banner.showRequest(agent: agent, reason: reason, seconds: max(remaining, 0.1))
            menu.addItem(info("\(agent) wants to use your Mac", symbolName: "hand.raised", bold: true))
            menu.addItem(info(reason, symbolName: "text.bubble"))
            menu.addItem(.separator())
            menu.addItem(action("Allow Now", symbolName: "checkmark.circle", #selector(allowNow)))
            menu.addItem(action("Not Now", symbolName: "xmark.circle", #selector(denyNow)))
        } else if state.isActive {
            button.image = statusIcon(filled: true, color: accent)
            button.toolTip = "\(agent) is using your Mac — \(reason)"
            banner.showActive(agent: agent, reason: reason, elapsed: Date().timeIntervalSince1970 - (state.since ?? 0))
            menu.addItem(info("\(agent) is using your Mac", symbolName: "hand.raised.fill", bold: true))
            menu.addItem(info(reason, symbolName: "text.bubble"))
            if let since = state.since {
                let f = DateFormatter()
                f.timeStyle = .short
                menu.addItem(info("Started at \(f.string(from: Date(timeIntervalSince1970: since)))", symbolName: "clock"))
            }
            menu.addItem(.separator())
            menu.addItem(action("Take Back Control", symbolName: "stop.circle", #selector(takeBack)))
        } else {
            button.image = statusIcon(filled: false)
            button.toolTip = "Backseat — no agent is using your Mac"
            banner.dismiss()
            menu.addItem(info("No agent is using your Mac", symbolName: "checkmark.circle"))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Backseat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func info(_ title: String, symbolName: String, bold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = symbol(symbolName, size: 13, weight: .regular)
        if bold {
            item.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0).bold()])
        }
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, symbolName: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.image = symbol(symbolName, size: 13, weight: .regular)
        item.target = self
        return item
    }

    @objc private func allowNow() { answer("allow") }
    @objc private func denyNow() { answer("deny") }

    @objc private func takeBack() {
        Seat.takeBack()
        render(.idle)
    }
}

extension NSFont {
    func bold() -> NSFont { NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask) }
}

func runApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
