import Foundation
import UIKit
import Display

public enum GroupRulesColors {
    /// The warm amber of the rules (a scroll in candlelight).
    public static let top = UIColor(rgb: 0xFFB340)
    public static let bottom = UIColor(rgb: 0xFF7A1A)
    /// The seal once they are accepted.
    public static let seal = UIColor(rgb: 0x34C759)
}

/// The rules' icon: an amber tile with a scroll on it. It can unroll (the paper opens between its two rollers and its
/// lines write themselves) and be sealed (a green seal with a check stamps onto its corner).
public final class GroupRulesIconView: UIView {
    private let tile = CAGradientLayer()
    private let canvas = CALayer()
    private let paper = CAShapeLayer()
    private let topRoller = CAShapeLayer()
    private let bottomRoller = CAShapeLayer()
    private var lines: [CAShapeLayer] = []
    private let seal = CAShapeLayer()
    private let sealCheck = CAShapeLayer()

    /// A small icon (in a list row) draws only the scroll in white, without the tile.
    public var isSmall = false {
        didSet {
            self.tile.isHidden = self.isSmall
            self.setNeedsLayout()
        }
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.tile.colors = [GroupRulesColors.top.cgColor, GroupRulesColors.bottom.cgColor]
        self.tile.startPoint = CGPoint(x: 0.2, y: 0.0)
        self.tile.endPoint = CGPoint(x: 0.8, y: 1.0)
        self.layer.addSublayer(self.tile)
        self.layer.addSublayer(self.canvas)
        self.canvas.addSublayer(self.paper)
        for _ in 0 ..< 3 {
            let line = CAShapeLayer()
            line.lineCap = .round
            line.fillColor = UIColor.clear.cgColor
            self.lines.append(line)
            self.canvas.addSublayer(line)
        }
        self.canvas.addSublayer(self.topRoller)
        self.canvas.addSublayer(self.bottomRoller)
        self.seal.fillColor = GroupRulesColors.seal.cgColor
        self.seal.strokeColor = UIColor.white.cgColor
        self.seal.opacity = 0.0
        self.layer.addSublayer(self.seal)
        self.sealCheck.fillColor = UIColor.clear.cgColor
        self.sealCheck.strokeColor = UIColor.white.cgColor
        self.sealCheck.lineCap = .round
        self.sealCheck.lineJoin = .round
        self.seal.addSublayer(self.sealCheck)
        self.applyColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyColors() {
        let color = UIColor.white
        self.paper.fillColor = UIColor.clear.cgColor
        self.paper.strokeColor = color.cgColor
        for roller in [self.topRoller, self.bottomRoller] {
            roller.fillColor = color.cgColor
        }
        for line in self.lines {
            line.strokeColor = color.cgColor
        }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        let side = min(bounds.width, bounds.height)
        // Drawn at the screen's resolution of what is shown, twice over (it grows larger than itself as it comes in).
        let contentsScale = UIScreenScale * 2.0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.tile.frame = bounds
        self.tile.cornerRadius = side * 0.29
        if #available(iOS 13.0, *) {
            self.tile.cornerCurve = .continuous
        }
        self.canvas.frame = bounds
        let glyph = self.isSmall ? bounds.insetBy(dx: side * 0.08, dy: side * 0.06) : bounds.insetBy(dx: side * 0.27, dy: side * 0.22)
        let lineWidth = max(1.6, glyph.width * 0.1)
        // The paper, between two rollers.
        let paperRect = CGRect(x: glyph.minX + glyph.width * 0.08, y: glyph.minY + lineWidth * 1.2, width: glyph.width * 0.84, height: glyph.height - lineWidth * 2.4)
        self.paper.frame = bounds
        self.paper.path = UIBezierPath(roundedRect: paperRect, cornerRadius: lineWidth * 0.6).cgPath
        self.paper.lineWidth = lineWidth
        let rollerHeight = lineWidth * 1.9
        self.topRoller.frame = bounds
        self.topRoller.path = UIBezierPath(roundedRect: CGRect(x: glyph.minX, y: glyph.minY, width: glyph.width, height: rollerHeight), cornerRadius: rollerHeight * 0.5).cgPath
        self.bottomRoller.frame = bounds
        self.bottomRoller.path = UIBezierPath(roundedRect: CGRect(x: glyph.minX, y: glyph.maxY - rollerHeight, width: glyph.width, height: rollerHeight), cornerRadius: rollerHeight * 0.5).cgPath
        // Three lines of writing on the paper, the last shorter.
        let inset = paperRect.width * 0.2
        for (index, line) in self.lines.enumerated() {
            let y = paperRect.minY + paperRect.height * (0.3 + CGFloat(index) * 0.2)
            let endX = paperRect.maxX - inset - (index == 2 ? paperRect.width * 0.22 : 0.0)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: paperRect.minX + inset, y: y))
            path.addLine(to: CGPoint(x: endX, y: y))
            line.frame = bounds
            line.path = path.cgPath
            line.lineWidth = lineWidth * 0.75
        }
        // The seal on the lower right corner, partly over the tile's edge.
        let sealSide = side * 0.44
        self.seal.frame = CGRect(x: bounds.maxX - sealSide * 0.82, y: bounds.maxY - sealSide * 0.82, width: sealSide, height: sealSide)
        self.seal.path = UIBezierPath(ovalIn: CGRect(origin: CGPoint(), size: CGSize(width: sealSide, height: sealSide))).cgPath
        self.seal.lineWidth = max(2.0, sealSide * 0.08)
        let check = UIBezierPath()
        check.move(to: CGPoint(x: sealSide * 0.28, y: sealSide * 0.52))
        check.addLine(to: CGPoint(x: sealSide * 0.44, y: sealSide * 0.67))
        check.addLine(to: CGPoint(x: sealSide * 0.72, y: sealSide * 0.36))
        self.sealCheck.frame = CGRect(origin: CGPoint(), size: CGSize(width: sealSide, height: sealSide))
        self.sealCheck.path = check.cgPath
        self.sealCheck.lineWidth = max(2.0, sealSide * 0.11)
        for layer in [self.tile, self.canvas, self.paper, self.topRoller, self.bottomRoller, self.seal, self.sealCheck] + self.lines {
            layer.contentsScale = contentsScale
        }
        CATransaction.commit()
    }

    /// The tile pops up turning, the scroll unrolls (the rollers part, the paper opens between them) and its lines write
    /// themselves one after another. Returns how long it takes.
    @discardableResult
    public func animateUnroll(delay: Double) -> Double {
        guard !UIAccessibility.isReduceMotionEnabled else {
            return 0.0
        }
        if !self.isSmall {
            rulesAddKeyframes(self.layer, keyPath: "transform.scale", values: [0.0, 1.22, 0.92, 1.05, 1.0], keyTimes: [0.0, 0.38, 0.62, 0.82, 1.0], duration: 0.75, delay: delay)
            rulesAddKeyframes(self.layer, keyPath: "transform.rotation.z", values: [-0.7, 0.14, -0.05, 0.0], keyTimes: [0.0, 0.42, 0.72, 1.0], duration: 0.75, delay: delay)
        }
        let open = delay + 0.25
        let half = self.bounds.height * 0.18
        rulesAddKeyframes(self.topRoller, keyPath: "transform.translation.y", values: [half, -2.0, 0.0], keyTimes: [0.0, 0.7, 1.0], duration: 0.5, delay: open, timing: .easeOut)
        rulesAddKeyframes(self.bottomRoller, keyPath: "transform.translation.y", values: [-half, 2.0, 0.0], keyTimes: [0.0, 0.7, 1.0], duration: 0.5, delay: open, timing: .easeOut)
        rulesAddKeyframes(self.paper, keyPath: "transform.scale.y", values: [0.06, 1.04, 1.0], keyTimes: [0.0, 0.7, 1.0], duration: 0.5, delay: open, timing: .easeOut)
        for (index, line) in self.lines.enumerated() {
            rulesAddKeyframes(line, keyPath: "strokeEnd", values: [0.0, 1.0], keyTimes: [0.0, 1.0], duration: 0.22, delay: open + 0.42 + Double(index) * 0.16, timing: .easeInEaseOut)
        }
        return open + 0.42 + 0.16 * 2.0 + 0.22 - delay
    }

    /// Whether the seal is on the corner (shown as it is, without stamping it).
    public var isSealed: Bool {
        get {
            return self.seal.opacity > 0.5
        }
        set {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // Animations held at their end would hide the new state.
            self.seal.removeAllAnimations()
            self.sealCheck.removeAllAnimations()
            self.seal.opacity = newValue ? 1.0 : 0.0
            self.sealCheck.strokeEnd = 1.0
            CATransaction.commit()
        }
    }

    /// The seal lifts off the corner: it grows a little and fades, turning away.
    public func liftSeal() {
        guard self.isSealed else {
            return
        }
        self.isSealed = false
        guard !UIAccessibility.isReduceMotionEnabled else {
            return
        }
        rulesAddKeyframes(self.seal, keyPath: "opacity", values: [1.0, 1.0, 0.0], keyTimes: [0.0, 0.3, 1.0], duration: 0.32, delay: 0.0, timing: .easeIn)
        rulesAddKeyframes(self.seal, keyPath: "transform.scale", values: [1.0, 1.12, 1.5], keyTimes: [0.0, 0.3, 1.0], duration: 0.32, delay: 0.0, timing: .easeIn)
        rulesAddKeyframes(self.seal, keyPath: "transform.rotation.z", values: [0.0, 0.5], keyTimes: [0.0, 1.0], duration: 0.32, delay: 0.0, timing: .easeIn)
        rulesAddKeyframes(self.seal, keyPath: "transform.translation.y", values: [0.0, -self.seal.bounds.height * 0.6], keyTimes: [0.0, 1.0], duration: 0.32, delay: 0.0, timing: .easeIn)
    }

    /// A green seal with a check stamps onto the corner: it falls from above large and turning, lands with a squash, its
    /// check is drawn, and a ring goes out of it.
    public func stampSeal(delay: Double) {
        self.isSealed = true
        guard !UIAccessibility.isReduceMotionEnabled else {
            return
        }
        rulesAddKeyframes(self.seal, keyPath: "opacity", values: [0.0, 1.0], keyTimes: [0.0, 1.0], duration: 0.08, delay: delay)
        rulesAddKeyframes(self.seal, keyPath: "transform.scale", values: [2.6, 0.82, 1.1, 0.96, 1.0], keyTimes: [0.0, 0.35, 0.55, 0.78, 1.0], duration: 0.55, delay: delay, timing: .easeOut)
        rulesAddKeyframes(self.seal, keyPath: "transform.rotation.z", values: [-1.2, 0.12, 0.0], keyTimes: [0.0, 0.4, 1.0], duration: 0.55, delay: delay, timing: .easeOut)
        rulesAddKeyframes(self.sealCheck, keyPath: "strokeEnd", values: [0.0, 0.0, 1.0], keyTimes: [0.0, 0.4, 1.0], duration: 0.5, delay: delay, timing: .easeOut)
        // The tile takes the stamp: a short squash.
        rulesAddKeyframes(self.layer, keyPath: "transform.scale", values: [1.0, 1.0, 0.9, 1.04, 1.0], keyTimes: [0.0, 0.3, 0.45, 0.7, 1.0], duration: 0.6, delay: delay)
        let ring = CAShapeLayer()
        let center = CGPoint(x: self.seal.frame.midX, y: self.seal.frame.midY)
        ring.path = UIBezierPath(arcCenter: CGPoint(), radius: self.seal.bounds.width * 0.5, startAngle: 0.0, endAngle: .pi * 2.0, clockwise: true).cgPath
        ring.position = center
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = GroupRulesColors.seal.cgColor
        ring.lineWidth = 2.5
        ring.opacity = 0.0
        ring.contentsScale = UIScreenScale * 2.0
        self.layer.insertSublayer(ring, below: self.seal)
        rulesAddKeyframes(ring, keyPath: "transform.scale", values: [0.9, 2.4], keyTimes: [0.0, 1.0], duration: 0.6, delay: delay + 0.2, timing: .easeOut)
        rulesAddKeyframes(ring, keyPath: "opacity", values: [0.0, 0.8, 0.0], keyTimes: [0.0, 0.2, 1.0], duration: 0.6, delay: delay + 0.2, timing: .easeOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.9, execute: { [weak ring] in
            ring?.removeFromSuperlayer()
        })
    }
}
