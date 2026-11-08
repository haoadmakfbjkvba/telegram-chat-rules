import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import ChatPresentationInterfaceState
import TelegramPresentationData
import ChatInputPanelNode
import AccountContext
import GlassBackgroundComponent
import ComponentFlow
import GroupRules

/// In place of the message field (or of Join) while the group's rules are to be accepted: a glass capsule with the
/// scroll, "Accept the group rules to join" and an arrow. It comes in by unrolling sideways like a scroll, and a tap
/// opens the rules. Once they are accepted from it, it says the account is joining until it is in.
final class GroupRulesInputPanelNode: ChatInputPanelNode {
    private let backgroundView: GlassBackgroundView
    private let contentView = UIView()
    private let badge = CAGradientLayer()
    private let iconView = GroupRulesIconView()
    private let titleView = RulesTextView()
    private let arrow = CAShapeLayer()
    private let spinner = CAShapeLayer()
    private let buttonNode: HighlightTrackingButtonNode
    private var prompt: GroupRulesPrompt = .join
    private var playsJoining = false
    private var didAppear = false
    private var lastSize = CGSize()

    override init() {
        self.backgroundView = GlassBackgroundView()
        self.buttonNode = HighlightTrackingButtonNode()
        super.init()

        self.contentView.isUserInteractionEnabled = false
        self.badge.colors = [GroupRulesColors.top.cgColor, GroupRulesColors.bottom.cgColor]
        self.badge.startPoint = CGPoint(x: 0.2, y: 0.0)
        self.badge.endPoint = CGPoint(x: 0.8, y: 1.0)
        self.contentView.layer.addSublayer(self.badge)
        self.iconView.isSmall = true
        self.contentView.addSubview(self.iconView)
        self.contentView.addSubview(self.titleView)
        self.arrow.fillColor = UIColor.clear.cgColor
        self.arrow.lineWidth = 2.0
        self.arrow.lineCap = .round
        self.arrow.lineJoin = .round
        self.arrow.contentsScale = UIScreenScale * 2.0
        self.contentView.layer.addSublayer(self.arrow)
        self.spinner.fillColor = UIColor.clear.cgColor
        self.spinner.lineWidth = 2.0
        self.spinner.lineCap = .round
        self.spinner.strokeEnd = 0.75
        self.spinner.opacity = 0.0
        self.spinner.contentsScale = UIScreenScale * 2.0
        self.contentView.layer.addSublayer(self.spinner)
        self.backgroundView.contentView.addSubview(self.contentView)
        self.view.addSubview(self.backgroundView)
        self.addSubnode(self.buttonNode)

        self.buttonNode.highligthedChanged = { [weak self] highlighted in
            guard let self else {
                return
            }
            let scale: CGFloat = highlighted ? 0.95 : 1.0
            UIView.animate(withDuration: highlighted ? 0.12 : 0.35, delay: 0.0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.0, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                self.backgroundView.transform = CGAffineTransform(scaleX: scale, y: scale)
            })
        }
        self.buttonNode.addTarget(self, action: #selector(self.buttonPressed), forControlEvents: .touchUpInside)
        self.buttonNode.view.isAccessibilityElement = true
        self.buttonNode.view.accessibilityTraits = [.button]
    }

    @objc private func buttonPressed() {
        guard self.prompt != .joining else {
            return
        }
        (self.interfaceInteraction?.chatController() as? ChatControllerImpl)?.presentGroupRules(fromPrompt: true)
    }

    func update(prompt: GroupRulesPrompt) {
        if prompt == .joining && self.prompt != .joining && self.didAppear {
            self.playsJoining = true
        }
        self.prompt = prompt
    }

    override func updateLayout(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, bottomInset: CGFloat, additionalSideInsets: UIEdgeInsets, maxHeight: CGFloat, maxOverlayHeight: CGFloat, isSecondary: Bool, transition: ContainedViewLayoutTransition, interfaceState: ChatPresentationInterfaceState, metrics: LayoutMetrics, deviceMetrics: DeviceMetrics, isMediaInputExpanded: Bool) -> CGFloat {
        let panelHeight = self.defaultHeight(metrics: metrics)
        let theme = interfaceState.theme
        let title: String
        switch self.prompt {
        case .join:
            title = interfaceState.strings.GroupRules_PromptJoin
        case .write:
            title = interfaceState.strings.GroupRules_PromptMember
        case .joining:
            title = interfaceState.strings.GroupRules_Joining
        }
        let isJoining = self.prompt == .joining
        let capsuleHeight: CGFloat = 46.0
        let sideInset: CGFloat = 12.0
        let capsuleWidth = width - leftInset - rightInset - sideInset * 2.0
        let badgeSide: CGFloat = 32.0
        let textX: CGFloat = 7.0 + badgeSide + 11.0
        let arrowWidth: CGFloat = isJoining ? 16.0 : 7.0
        let titleSize = self.titleView.update(text: NSAttributedString(string: title, attributes: [.font: Font.semibold(16.0), .foregroundColor: theme.chat.inputPanel.panelControlAccentColor]), width: max(1.0, capsuleWidth - textX - arrowWidth - 26.0), maxLines: 1)

        let capsuleFrame = CGRect(x: leftInset + sideInset, y: floor((panelHeight - capsuleHeight) * 0.5), width: capsuleWidth, height: capsuleHeight)
        self.backgroundView.bounds = CGRect(origin: CGPoint(), size: capsuleFrame.size)
        self.backgroundView.center = CGPoint(x: capsuleFrame.midX, y: capsuleFrame.midY)
        self.backgroundView.update(size: capsuleFrame.size, cornerRadius: capsuleHeight * 0.5, isDark: theme.overallDarkAppearance, tintColor: .init(kind: .panel), transition: ComponentTransition(transition))
        self.contentView.frame = CGRect(origin: CGPoint(), size: capsuleFrame.size)
        self.buttonNode.frame = capsuleFrame

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.badge.frame = CGRect(x: 7.0, y: floor((capsuleHeight - badgeSide) * 0.5), width: badgeSide, height: badgeSide)
        self.badge.cornerRadius = badgeSide * 0.5
        self.badge.contentsScale = UIScreenScale * 2.0
        CATransaction.commit()
        self.iconView.frame = self.badge.frame.insetBy(dx: 7.0, dy: 7.0)
        // The text and the arrow, centered together in what the badge leaves.
        let groupWidth = titleSize.width + 10.0 + arrowWidth
        let groupX = textX + max(0.0, floor((capsuleWidth - textX - 16.0 - groupWidth) * 0.5))
        self.titleView.frame = CGRect(x: groupX, y: floor((capsuleHeight - titleSize.height) * 0.5), width: titleSize.width, height: titleSize.height)
        let arrowX = groupX + titleSize.width + 10.0
        let arrowPath = UIBezierPath()
        arrowPath.move(to: CGPoint(x: arrowX, y: capsuleHeight * 0.5 - 6.0))
        arrowPath.addLine(to: CGPoint(x: arrowX + arrowWidth, y: capsuleHeight * 0.5))
        arrowPath.addLine(to: CGPoint(x: arrowX, y: capsuleHeight * 0.5 + 6.0))
        self.arrow.frame = self.contentView.bounds
        self.arrow.path = arrowPath.cgPath
        self.arrow.strokeColor = theme.chat.inputPanel.panelControlAccentColor.cgColor
        // While joining, a turning arc in the arrow's place.
        let spinnerSide: CGFloat = 16.0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.spinner.bounds = CGRect(origin: CGPoint(), size: CGSize(width: spinnerSide, height: spinnerSide))
        self.spinner.position = CGPoint(x: arrowX + spinnerSide * 0.5, y: capsuleHeight * 0.5)
        self.spinner.path = UIBezierPath(ovalIn: CGRect(origin: CGPoint(), size: CGSize(width: spinnerSide, height: spinnerSide)).insetBy(dx: 1.0, dy: 1.0)).cgPath
        self.spinner.strokeColor = theme.chat.inputPanel.panelControlAccentColor.cgColor
        self.arrow.opacity = isJoining ? 0.0 : 1.0
        self.spinner.opacity = isJoining ? 1.0 : 0.0
        if isJoining {
            self.badge.colors = [GroupRulesColors.seal.withMultipliedBrightnessBy(1.12).cgColor, GroupRulesColors.seal.cgColor]
        }
        CATransaction.commit()
        if isJoining && self.spinner.animation(forKey: "spin") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0.0
            spin.toValue = Double.pi * 2.0
            spin.duration = 0.8
            spin.repeatCount = .infinity
            self.spinner.add(spin, forKey: "spin")
        }
        self.buttonNode.isUserInteractionEnabled = !isJoining
        self.buttonNode.view.accessibilityLabel = title
        self.lastSize = capsuleFrame.size
        if self.playsJoining {
            self.playsJoining = false
            self.animateJoining()
        }

        if !self.didAppear {
            self.didAppear = true
            DispatchQueue.main.async { [weak self] in
                self?.animateAppearance()
            }
        }
        return panelHeight
    }

    /// The capsule unrolls sideways out of its badge like a scroll, a little large; the badge pops up turning and its
    /// scroll unrolls; the words rise in letter by letter; the arrow slides in; light passes over, and the badge sends
    /// out two rings to be noticed.
    private func animateAppearance() {
        guard !UIAccessibility.isReduceMotionEnabled, self.lastSize.width > 0.0 else {
            return
        }
        let size = self.lastSize
        let startWidth = size.height
        let layer = self.backgroundView.layer
        // The glass is laid out at its full size; it opens from a circle by a mask, not by resizing.
        let mask = CAShapeLayer()
        mask.frame = CGRect(origin: CGPoint(), size: size)
        mask.path = UIBezierPath(roundedRect: CGRect(origin: CGPoint(), size: size), cornerRadius: size.height * 0.5).cgPath
        mask.fillColor = UIColor.white.cgColor
        layer.mask = mask
        let fromPath = UIBezierPath(roundedRect: CGRect(x: (size.width - startWidth) * 0.5, y: 0.0, width: startWidth, height: size.height), cornerRadius: size.height * 0.5).cgPath
        let overPath = UIBezierPath(roundedRect: CGRect(x: -6.0, y: -2.0, width: size.width + 12.0, height: size.height + 4.0), cornerRadius: size.height * 0.5 + 2.0).cgPath
        let toPath = UIBezierPath(roundedRect: CGRect(origin: CGPoint(), size: size), cornerRadius: size.height * 0.5).cgPath
        rulesAddKeyframes(mask, keyPath: "path", values: [fromPath, fromPath, overPath, toPath], keyTimes: [0.0, 0.18, 0.7, 1.0], duration: 0.85, delay: 0.0, timing: .easeOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: { [weak layer] in
            layer?.mask = nil
        })
        // The whole capsule pops in and holds a little large for a moment.
        rulesAddKeyframes(layer, keyPath: "transform.scale", values: [0.6, 1.08, 1.05, 1.06, 1.0], keyTimes: [0.0, 0.22, 0.5, 0.75, 1.0], duration: 1.8, delay: 0.0)
        rulesAddKeyframes(layer, keyPath: "opacity", values: [0.0, 1.0], keyTimes: [0.0, 1.0], duration: 0.15, delay: 0.0)

        // The badge, travelling from the middle to its place as the capsule opens.
        let badgeShift = size.width * 0.5 - self.badge.frame.midX
        for badgeLayer in [self.badge, self.iconView.layer] {
            rulesAddKeyframes(badgeLayer, keyPath: "transform.translation.x", values: [badgeShift, badgeShift, 0.0], keyTimes: [0.0, 0.18, 1.0], duration: 0.85, delay: 0.0, timing: .easeOut)
        }
        rulesAddKeyframes(self.badge, keyPath: "transform.scale", values: [0.2, 1.3, 0.9, 1.0], keyTimes: [0.0, 0.35, 0.65, 1.0], duration: 0.6, delay: 0.0)
        rulesAddKeyframes(self.badge, keyPath: "transform.rotation.z", values: [-1.0, 0.18, 0.0], keyTimes: [0.0, 0.45, 1.0], duration: 0.6, delay: 0.0)
        self.iconView.animateUnroll(delay: 0.15)

        let textEnd = self.titleView.animateLettersIn(delay: 0.45, stagger: 0.02, offset: 9.0)
        // The arrow, or (joining already) the turning arc in its place.
        let trailing: CALayer = self.prompt == .joining ? self.spinner : self.arrow
        rulesAddKeyframes(trailing, keyPath: "opacity", values: [0.0, 1.0], keyTimes: [0.0, 1.0], duration: 0.25, delay: textEnd - 0.1)
        rulesAddKeyframes(trailing, keyPath: "transform.translation.x", values: [-10.0, 3.0, 0.0], keyTimes: [0.0, 0.6, 1.0], duration: 0.45, delay: textEnd - 0.1, timing: .easeOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + textEnd, execute: { [weak self] in
            guard let self else {
                return
            }
            rulesAnimateSheen(over: self.backgroundView, cornerRadius: self.lastSize.height * 0.5, delay: 0.0, duration: 0.9, alpha: 0.4)
            for index in 0 ..< 2 {
                self.sendRing(delay: Double(index) * 0.35)
            }
        })
    }

    /// Accepted: the badge turns green with a pop and a ring, the new words rise in, the arrow gives way to the arc.
    private func animateJoining() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            return
        }
        let colors = CABasicAnimation(keyPath: "colors")
        colors.fromValue = [GroupRulesColors.top.cgColor, GroupRulesColors.bottom.cgColor]
        colors.toValue = self.badge.colors
        colors.duration = 0.3
        self.badge.add(colors, forKey: "colors")
        rulesAddKeyframes(self.badge, keyPath: "transform.scale", values: [1.0, 1.3, 0.92, 1.0], keyTimes: [0.0, 0.4, 0.75, 1.0], duration: 0.45, delay: 0.0)
        self.sendRing(delay: 0.1, color: GroupRulesColors.seal)
        let _ = self.titleView.animateLettersIn(delay: 0.05, stagger: 0.014, offset: 8.0)
        rulesAddKeyframes(self.arrow, keyPath: "opacity", values: [1.0, 0.0], keyTimes: [0.0, 1.0], duration: 0.15, delay: 0.0)
        rulesAddKeyframes(self.spinner, keyPath: "opacity", values: [0.0, 1.0], keyTimes: [0.0, 1.0], duration: 0.25, delay: 0.2)
        rulesAddKeyframes(self.spinner, keyPath: "transform.scale", values: [0.3, 1.15, 1.0], keyTimes: [0.0, 0.6, 1.0], duration: 0.35, delay: 0.2)
    }

    /// A ring going out from the badge.
    private func sendRing(delay: Double, color: UIColor = GroupRulesColors.bottom) {
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(arcCenter: CGPoint(), radius: self.badge.bounds.width * 0.5, startAngle: 0.0, endAngle: .pi * 2.0, clockwise: true).cgPath
        ring.position = CGPoint(x: self.badge.frame.midX, y: self.badge.frame.midY)
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = color.cgColor
        ring.lineWidth = 2.0
        ring.opacity = 0.0
        ring.contentsScale = UIScreenScale * 2.0
        self.contentView.layer.insertSublayer(ring, below: self.badge)
        rulesAddKeyframes(ring, keyPath: "transform.scale", values: [0.9, 1.9], keyTimes: [0.0, 1.0], duration: 0.7, delay: delay, timing: .easeOut)
        rulesAddKeyframes(ring, keyPath: "opacity", values: [0.0, 0.8, 0.0], keyTimes: [0.0, 0.2, 1.0], duration: 0.7, delay: delay, timing: .easeOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.8, execute: { [weak ring] in
            ring?.removeFromSuperlayer()
        })
    }

    override func minimalHeight(interfaceState: ChatPresentationInterfaceState, metrics: LayoutMetrics) -> CGFloat {
        return self.defaultHeight(metrics: metrics)
    }
}
