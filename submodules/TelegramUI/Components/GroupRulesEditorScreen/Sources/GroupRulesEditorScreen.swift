import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import AccountContext
import ComponentFlow
import ViewControllerComponent
import MultilineTextComponent
import ButtonComponent
import GroupRules

private let ruleFont = Font.regular(17.0)
private let rowMinHeight: CGFloat = 52.0
private let badgeSide: CGFloat = 28.0
private let rowTextX: CGFloat = 16.0 + badgeSide + 14.0
private let deleteSide: CGFloat = 44.0

// MARK: - A rule

/// One rule being written: its number on the path, its text, and a button that takes it out. While it is being written a
/// ring around the number fills with how much of the rule's room is used.
private final class GroupRulesEditorRuleRow: UIView, UITextViewDelegate {
    let id: Int
    let badge = UIView()
    let numberLabel = UILabel()
    let ringTrack = CAShapeLayer()
    let ring = CAShapeLayer()
    let textView = UITextView()
    let placeholder = UILabel()
    let deleteButton = HighlightTrackingButton()
    let deleteBackground = CAShapeLayer()
    let deleteBar = CAShapeLayer()
    let separator = UIView()

    private(set) var number = 0
    /// Being taken out (its end of editing is not a rule written).
    var isRemoving = false
    private var theme: PresentationTheme?
    private var textAtFocus = ""

    var changed: ((GroupRulesEditorRuleRow) -> Void)?
    var focusChanged: ((GroupRulesEditorRuleRow, Bool) -> Void)?
    var deleteRequested: ((GroupRulesEditorRuleRow) -> Void)?

    init(id: Int, text: String) {
        self.id = id
        super.init(frame: CGRect())

        self.badge.backgroundColor = GroupRulesColors.bottom
        self.badge.layer.cornerRadius = badgeSide * 0.5
        self.addSubview(self.badge)
        self.numberLabel.font = Font.with(size: 15.0, design: .round, weight: .bold)
        self.numberLabel.textColor = .white
        self.numberLabel.textAlignment = .center
        self.badge.addSubview(self.numberLabel)

        for layer in [self.ringTrack, self.ring] {
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = 2.0
            layer.lineCap = .round
            layer.opacity = 0.0
            layer.contentsScale = UIScreenScale * 2.0
            self.layer.addSublayer(layer)
        }
        self.ring.strokeEnd = 0.0

        self.textView.text = text
        self.textView.font = ruleFont
        self.textView.backgroundColor = .clear
        self.textView.isScrollEnabled = false
        self.textView.textContainerInset = .zero
        self.textView.textContainer.lineFragmentPadding = 0.0
        self.textView.returnKeyType = .done
        self.textView.enablesReturnKeyAutomatically = false
        self.textView.delegate = self
        self.addSubview(self.textView)
        self.placeholder.font = ruleFont
        self.placeholder.isUserInteractionEnabled = false
        self.placeholder.isAccessibilityElement = false
        self.placeholder.isHidden = !text.isEmpty
        self.addSubview(self.placeholder)

        self.deleteBackground.contentsScale = UIScreenScale * 2.0
        self.deleteBar.contentsScale = UIScreenScale * 2.0
        self.deleteBar.lineCap = .round
        self.deleteBar.lineWidth = 2.2
        self.deleteButton.layer.addSublayer(self.deleteBackground)
        self.deleteButton.layer.addSublayer(self.deleteBar)
        self.deleteButton.addTarget(self, action: #selector(self.deletePressed), for: .touchUpInside)
        self.deleteButton.highligthedChanged = { [weak self] highlighted in
            guard let self else {
                return
            }
            let scale: CGFloat = highlighted ? 0.82 : 1.0
            UIView.animate(withDuration: highlighted ? 0.1 : 0.3, delay: 0.0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.0, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                self.deleteButton.transform = CGAffineTransform(scaleX: scale, y: scale)
            })
        }
        self.addSubview(self.deleteButton)
        self.addSubview(self.separator)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var text: String {
        return self.textView.text ?? ""
    }

    var trimmedText: String {
        return self.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func update(theme: PresentationTheme, strings: PresentationStrings, number: Int, animated: Bool) {
        if self.theme !== theme {
            self.theme = theme
            self.textView.textColor = theme.list.itemPrimaryTextColor
            self.textView.tintColor = theme.list.itemAccentColor
            self.textView.keyboardAppearance = theme.rootController.keyboardColor.keyboardAppearance
            self.placeholder.textColor = theme.list.itemPlaceholderTextColor
            self.separator.backgroundColor = theme.list.itemBlocksSeparatorColor
            self.ringTrack.strokeColor = GroupRulesColors.bottom.withAlphaComponent(0.18).cgColor
            self.deleteBackground.fillColor = theme.list.itemDestructiveColor.withAlphaComponent(0.13).cgColor
            self.deleteBar.strokeColor = theme.list.itemDestructiveColor.cgColor
            self.updateRing()
        }
        self.placeholder.text = strings.GroupRules_RulePlaceholder
        self.deleteButton.accessibilityLabel = strings.GroupRules_DeleteRule
        if self.number != number {
            let previous = self.number
            self.number = number
            self.numberLabel.text = "\(number)"
            self.textView.accessibilityLabel = strings.GroupRules_RuleNumber("\(number)").string
            if animated && previous != 0 && !UIAccessibility.isReduceMotionEnabled {
                // The number rolls to its new value, the way the rules close up.
                let transition = CATransition()
                transition.type = .push
                transition.subtype = number < previous ? .fromTop : .fromBottom
                transition.duration = 0.32
                transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.numberLabel.layer.add(transition, forKey: "number")
            }
        }
    }

    /// Lays the row out at `width` and returns its height (taller as its rule wraps).
    func layout(width: CGFloat) -> CGFloat {
        let textWidth = max(1.0, width - rowTextX - deleteSide - 4.0)
        let textHeight = ceil(self.textView.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height)
        let lineHeight = ceil(ruleFont.lineHeight)
        let textY = floor((rowMinHeight - lineHeight) * 0.5)
        let height = max(rowMinHeight, textY * 2.0 + textHeight)

        let badgeFrame = CGRect(x: 16.0, y: floor((rowMinHeight - badgeSide) * 0.5), width: badgeSide, height: badgeSide)
        self.badge.bounds = CGRect(origin: CGPoint(), size: badgeFrame.size)
        self.badge.center = CGPoint(x: badgeFrame.midX, y: badgeFrame.midY)
        self.numberLabel.frame = self.badge.bounds

        let ringRadius = badgeSide * 0.5 + 3.5
        let ringPath = UIBezierPath(arcCenter: CGPoint(x: ringRadius, y: ringRadius), radius: ringRadius, startAngle: -.pi * 0.5, endAngle: .pi * 1.5, clockwise: true).cgPath
        for layer in [self.ringTrack, self.ring] {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = CGRect(x: badgeFrame.midX - ringRadius, y: badgeFrame.midY - ringRadius, width: ringRadius * 2.0, height: ringRadius * 2.0)
            layer.path = ringPath
            CATransaction.commit()
        }

        self.textView.frame = CGRect(x: rowTextX, y: textY, width: textWidth, height: max(lineHeight, textHeight))
        self.placeholder.frame = CGRect(x: rowTextX, y: textY, width: textWidth, height: lineHeight)

        self.deleteButton.frame = CGRect(x: width - deleteSide - 4.0, y: floor((rowMinHeight - deleteSide) * 0.5), width: deleteSide, height: deleteSide)
        let glyphSide: CGFloat = 22.0
        let glyphRect = CGRect(x: (deleteSide - glyphSide) * 0.5, y: (deleteSide - glyphSide) * 0.5, width: glyphSide, height: glyphSide)
        let bar = UIBezierPath()
        bar.move(to: CGPoint(x: glyphRect.midX - 5.0, y: glyphRect.midY))
        bar.addLine(to: CGPoint(x: glyphRect.midX + 5.0, y: glyphRect.midY))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.deleteBackground.frame = CGRect(origin: CGPoint(), size: CGSize(width: deleteSide, height: deleteSide))
        self.deleteBackground.path = UIBezierPath(ovalIn: glyphRect).cgPath
        self.deleteBar.frame = self.deleteBackground.frame
        self.deleteBar.path = bar.cgPath
        CATransaction.commit()

        self.separator.frame = CGRect(x: rowTextX, y: height - UIScreenPixel, width: width - rowTextX, height: UIScreenPixel)
        return height
    }

    private func updateRing() {
        let count = self.text.count
        let fraction = min(1.0, CGFloat(count) / CGFloat(GroupRules.maxRuleLength))
        self.ring.strokeEnd = fraction
        let nearLimit = count >= GroupRules.maxRuleLength - 10
        self.ring.strokeColor = (nearLimit ? (self.theme?.list.itemDestructiveColor ?? .red) : GroupRulesColors.bottom).cgColor
    }

    // MARK: Animations

    /// The plus of "Add Rule" turns into this rule's number: the badge spins half a turn as its color warms from the
    /// accent to amber, the plus fades as the number grows in, and a ring goes out of it.
    func animateFromPlus(accentColor: UIColor) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            return
        }
        self.badge.backgroundColor = accentColor
        UIView.animate(withDuration: 0.4, delay: 0.06, options: [.curveEaseInOut], animations: {
            self.badge.backgroundColor = GroupRulesColors.bottom
        })
        // From half a turn (where the plus looks as it did) to upright, a little past it first.
        rulesAddKeyframes(self.badge.layer, keyPath: "transform.rotation.z", values: [Double.pi, -Double.pi * 0.08, 0.0], keyTimes: [0.0, 0.7, 1.0], duration: 0.55, delay: 0.0, timing: .easeOut)
        rulesAddKeyframes(self.badge.layer, keyPath: "transform.scale", values: [1.0, 1.28, 0.92, 1.0], keyTimes: [0.0, 0.4, 0.72, 1.0], duration: 0.55, delay: 0.0)
        let plus = CAShapeLayer()
        let side = badgeSide
        let path = UIBezierPath()
        path.move(to: CGPoint(x: side * 0.5, y: side * 0.3))
        path.addLine(to: CGPoint(x: side * 0.5, y: side * 0.7))
        path.move(to: CGPoint(x: side * 0.3, y: side * 0.5))
        path.addLine(to: CGPoint(x: side * 0.7, y: side * 0.5))
        plus.path = path.cgPath
        plus.frame = CGRect(origin: CGPoint(), size: CGSize(width: side, height: side))
        plus.strokeColor = UIColor.white.cgColor
        plus.lineWidth = 2.4
        plus.lineCap = .round
        plus.contentsScale = UIScreenScale * 2.0
        plus.opacity = 0.0
        self.badge.layer.addSublayer(plus)
        rulesAddKeyframes(plus, keyPath: "opacity", values: [1.0, 1.0, 0.0], keyTimes: [0.0, 0.3, 1.0], duration: 0.3, delay: 0.0, timing: .easeIn)
        rulesAddKeyframes(plus, keyPath: "transform.scale", values: [1.0, 0.3], keyTimes: [0.0, 1.0], duration: 0.3, delay: 0.0, timing: .easeIn)
        rulesAddKeyframes(self.numberLabel.layer, keyPath: "opacity", values: [0.0, 0.0, 1.0], keyTimes: [0.0, 0.4, 1.0], duration: 0.4, delay: 0.0)
        rulesAddKeyframes(self.numberLabel.layer, keyPath: "transform.scale", values: [0.2, 0.2, 1.22, 1.0], keyTimes: [0.0, 0.35, 0.75, 1.0], duration: 0.5, delay: 0.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: { [weak plus] in
            plus?.removeFromSuperlayer()
        })
        self.pulse(delay: 0.22, color: GroupRulesColors.top)
        rulesAnimateRiseIn(self.placeholder.layer, delay: 0.18, offset: 0.0, scale: 1.0, blur: 6.0)
        rulesAddKeyframes(self.placeholder.layer, keyPath: "transform.translation.x", values: [-14.0, 0.0], keyTimes: [0.0, 1.0], duration: 0.45, delay: 0.18, timing: .easeOut)
        rulesAnimateRiseIn(self.deleteButton.layer, delay: 0.3, offset: 0.0, scale: 0.4, blur: 0.0)
    }

    /// A ring of `color` goes out of the number.
    func pulse(delay: Double, color: UIColor) {
        let ring = CAShapeLayer()
        let radius = badgeSide * 0.5
        ring.path = UIBezierPath(arcCenter: CGPoint(), radius: radius, startAngle: 0.0, endAngle: .pi * 2.0, clockwise: true).cgPath
        ring.position = self.badge.center
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = color.cgColor
        ring.lineWidth = 2.5
        ring.opacity = 0.0
        ring.contentsScale = UIScreenScale * 2.0
        self.layer.insertSublayer(ring, below: self.badge.layer)
        rulesAddKeyframes(ring, keyPath: "transform.scale", values: [0.9, 2.1], keyTimes: [0.0, 1.0], duration: 0.6, delay: delay, timing: .easeOut)
        rulesAddKeyframes(ring, keyPath: "opacity", values: [0.0, 0.85, 0.0], keyTimes: [0.0, 0.15, 1.0], duration: 0.6, delay: delay, timing: .easeOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.7, execute: { [weak ring] in
            ring?.removeFromSuperlayer()
        })
    }

    /// The rule is written: the ring closes into the number, which stamps once.
    private func animateInscribed() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            return
        }
        rulesAddKeyframes(self.ring, keyPath: "transform.scale", values: [1.0, 0.75], keyTimes: [0.0, 1.0], duration: 0.25, delay: 0.0, timing: .easeIn)
        rulesAddKeyframes(self.badge.layer, keyPath: "transform.scale", values: [1.0, 1.0, 1.2, 0.94, 1.0], keyTimes: [0.0, 0.3, 0.55, 0.8, 1.0], duration: 0.5, delay: 0.0)
        self.pulse(delay: 0.15, color: GroupRulesColors.top)
    }

    /// The row goes: its text drifts away and fades, its number spins out.
    func animateOut(completion: @escaping () -> Void) {
        self.isUserInteractionEnabled = false
        guard !UIAccessibility.isReduceMotionEnabled else {
            completion()
            return
        }
        UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveEaseIn], animations: {
            self.textView.alpha = 0.0
            self.textView.transform = CGAffineTransform(translationX: 28.0, y: 0.0).scaledBy(x: 0.92, y: 0.92)
            self.placeholder.alpha = 0.0
            self.deleteButton.alpha = 0.0
            self.deleteButton.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            self.separator.alpha = 0.0
        })
        // It ends hidden (the animations are taken off when they end, a moment before the row is).
        self.badge.layer.opacity = 0.0
        rulesAddKeyframes(self.badge.layer, keyPath: "opacity", values: [1.0, 1.0, 0.0], keyTimes: [0.0, 0.7, 1.0], duration: 0.3, delay: 0.0, timing: .easeIn)
        rulesAddKeyframes(self.badge.layer, keyPath: "transform.rotation.z", values: [0.0, Double.pi * 0.9], keyTimes: [0.0, 1.0], duration: 0.3, delay: 0.0, timing: .easeIn)
        rulesAddKeyframes(self.badge.layer, keyPath: "transform.scale", values: [1.0, 1.15, 0.0], keyTimes: [0.0, 0.3, 1.0], duration: 0.3, delay: 0.0, timing: .easeIn)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: completion)
    }

    // MARK: Actions

    @objc private func deletePressed() {
        self.deleteRequested?(self)
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            textView.resignFirstResponder()
            return false
        }
        // Text being composed (a keyboard that builds characters) is checked once it is done, in textViewDidChange.
        if textView.markedTextRange != nil {
            return true
        }
        let current = (textView.text ?? "") as NSString
        // One line each: line breaks pasted in become spaces.
        var replacement = text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        let room = GroupRules.maxRuleLength - (current.replacingCharacters(in: range, with: "") as String).count
        if !replacement.isEmpty && replacement.count > room {
            // Only what fits goes in, where it was put; the rest of the rule stays.
            replacement = String(replacement.prefix(max(0, room)))
            self.signalFull()
            if replacement.isEmpty {
                return false
            }
        }
        if replacement != text {
            textView.textStorage.replaceCharacters(in: range, with: replacement)
            textView.selectedRange = NSRange(location: range.location + (replacement as NSString).length, length: 0)
            // Undo would not know of this change (and could undo past the text).
            textView.undoManager?.removeAllActions()
            self.textViewDidChange(textView)
            return false
        }
        return true
    }

    /// The rule is as long as it can be: a short shake of its number.
    private func signalFull() {
        HapticFeedback().error()
        if !UIAccessibility.isReduceMotionEnabled {
            rulesAddKeyframes(self.badge.layer, keyPath: "transform.translation.x", values: [0.0, -4.0, 4.0, -2.0, 0.0], keyTimes: [0.0, 0.25, 0.5, 0.75, 1.0], duration: 0.3, delay: 0.0)
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        if textView.markedTextRange == nil, self.text.count > GroupRules.maxRuleLength {
            // A composed word that went over the limit.
            textView.text = String(self.text.prefix(GroupRules.maxRuleLength))
            textView.undoManager?.removeAllActions()
            self.signalFull()
        }
        self.placeholder.isHidden = !self.text.isEmpty
        self.updateRing()
        self.changed?(self)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        self.textAtFocus = self.text
        self.updateRing()
        for layer in [self.ringTrack, self.ring] {
            layer.removeAllAnimations()
            layer.opacity = 1.0
            if !UIAccessibility.isReduceMotionEnabled {
                rulesAddKeyframes(layer, keyPath: "opacity", values: [0.0, 1.0], keyTimes: [0.0, 1.0], duration: 0.25, delay: 0.0)
                rulesAddKeyframes(layer, keyPath: "transform.scale", values: [0.7, 1.08, 1.0], keyTimes: [0.0, 0.6, 1.0], duration: 0.4, delay: 0.0)
            }
        }
        self.focusChanged?(self, true)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        for layer in [self.ringTrack, self.ring] {
            layer.removeAllAnimations()
            layer.opacity = 0.0
            if !UIAccessibility.isReduceMotionEnabled {
                rulesAddKeyframes(layer, keyPath: "opacity", values: [1.0, 0.0], keyTimes: [0.0, 1.0], duration: 0.25, delay: 0.0)
            }
        }
        let written = !self.isRemoving && !self.trimmedText.isEmpty && self.trimmedText != self.textAtFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        if written {
            self.animateInscribed()
        }
        self.focusChanged?(self, false)
    }
}

// MARK: - Add Rule

/// The row at the end of the rules: a plus and "Add Rule", in the accent color.
private final class GroupRulesEditorAddRow: HighlightTrackingButton {
    let plusBadge = UIView()
    let plus = CAShapeLayer()
    let titleLabel2 = UILabel()
    private var theme: PresentationTheme?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.plusBadge.isUserInteractionEnabled = false
        self.plusBadge.layer.cornerRadius = badgeSide * 0.5
        self.addSubview(self.plusBadge)
        self.plus.strokeColor = UIColor.white.cgColor
        self.plus.lineWidth = 2.4
        self.plus.lineCap = .round
        self.plus.contentsScale = UIScreenScale * 2.0
        self.plusBadge.layer.addSublayer(self.plus)
        self.titleLabel2.font = ruleFont
        self.titleLabel2.isUserInteractionEnabled = false
        self.addSubview(self.titleLabel2)
        self.highligthedChanged = { [weak self] highlighted in
            guard let self, let theme = self.theme else {
                return
            }
            if highlighted {
                self.backgroundColor = theme.list.itemHighlightedBackgroundColor
            } else {
                UIView.animate(withDuration: 0.3, animations: {
                    self.backgroundColor = .clear
                })
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(theme: PresentationTheme, strings: PresentationStrings, width: CGFloat) {
        if self.theme !== theme {
            self.theme = theme
            self.plusBadge.backgroundColor = theme.list.itemAccentColor
            self.titleLabel2.textColor = theme.list.itemAccentColor
        }
        self.titleLabel2.text = strings.GroupRules_AddRule
        self.accessibilityLabel = strings.GroupRules_AddRule
        self.accessibilityTraits = .button
        let badgeFrame = CGRect(x: 16.0, y: floor((rowMinHeight - badgeSide) * 0.5), width: badgeSide, height: badgeSide)
        self.plusBadge.bounds = CGRect(origin: CGPoint(), size: badgeFrame.size)
        self.plusBadge.center = CGPoint(x: badgeFrame.midX, y: badgeFrame.midY)
        let side = badgeSide
        let path = UIBezierPath()
        path.move(to: CGPoint(x: side * 0.5, y: side * 0.3))
        path.addLine(to: CGPoint(x: side * 0.5, y: side * 0.7))
        path.move(to: CGPoint(x: side * 0.3, y: side * 0.5))
        path.addLine(to: CGPoint(x: side * 0.7, y: side * 0.5))
        self.plus.frame = self.plusBadge.bounds
        self.plus.path = path.cgPath
        let lineHeight = ceil(ruleFont.lineHeight)
        self.titleLabel2.frame = CGRect(x: rowTextX, y: floor((rowMinHeight - lineHeight) * 0.5), width: max(1.0, width - rowTextX - 16.0), height: lineHeight)
    }

    /// A fresh plus pops in (the last one became a rule's number).
    func animateNewPlus(delay: Double) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            return
        }
        rulesAddKeyframes(self.plusBadge.layer, keyPath: "transform.scale", values: [0.0, 1.22, 0.94, 1.0], keyTimes: [0.0, 0.45, 0.75, 1.0], duration: 0.5, delay: delay)
        rulesAddKeyframes(self.plusBadge.layer, keyPath: "transform.rotation.z", values: [-Double.pi * 0.5, 0.0], keyTimes: [0.0, 1.0], duration: 0.5, delay: delay, timing: .easeOut)
    }
}

// MARK: - The screen

final class GroupRulesEditorScreenComponent: Component {
    typealias EnvironmentType = ViewControllerComponentContainer.Environment

    let context: AccountContext
    let peerId: EnginePeer.Id
    let groupTitle: String
    /// The description without its rules, and the rules, as they were when the screen opened.
    let descriptionText: String
    let initialRules: GroupRules?
    /// The word the rules are headed with in the description, if they are there (kept as it is when they are saved).
    let blockHeader: String?

    init(context: AccountContext, peerId: EnginePeer.Id, groupTitle: String, descriptionText: String, initialRules: GroupRules?, blockHeader: String?) {
        self.context = context
        self.peerId = peerId
        self.groupTitle = groupTitle
        self.descriptionText = descriptionText
        self.initialRules = initialRules
        self.blockHeader = blockHeader
    }

    static func ==(lhs: GroupRulesEditorScreenComponent, rhs: GroupRulesEditorScreenComponent) -> Bool {
        return lhs.context === rhs.context && lhs.peerId == rhs.peerId && lhs.groupTitle == rhs.groupTitle && lhs.descriptionText == rhs.descriptionText && lhs.initialRules == rhs.initialRules && lhs.blockHeader == rhs.blockHeader
    }

    final class View: UIView {
        private let scrollView = UIScrollView()
        private let navigationTitle = ComponentView<Empty>()
        private let iconView = GroupRulesIconView()
        private let subtitleView = RulesTextView()
        private let sectionHeader = UILabel()
        private let card = UIView()
        private let pathTrack = CAShapeLayer()
        private let path = CAShapeLayer()
        private var rows: [GroupRulesEditorRuleRow] = []
        private let addRow = GroupRulesEditorAddRow()
        private let footer = UILabel()
        private let toggleCard = UIView()
        private let sealTile = UIView()
        private let sealCheck = CAShapeLayer()
        private let toggleTitle = UILabel()
        private let toggleSwitch = UISwitch()
        private let toggleFooter = UILabel()
        private let saveButton = ComponentView<Empty>()

        private var component: GroupRulesEditorScreenComponent?
        private var environment: EnvironmentType?
        private weak var state: EmptyComponentState?
        private var isUpdating = false

        private var nextRowId = 0
        private var requiresAcceptance = true
        private var isSaving = false
        private var didSave = false
        private var didAppear = false
        private var focusedRowId: Int?
        private var lastInputHeight: CGFloat = 0.0
        private let haptic = HapticFeedback()

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.scrollView.showsVerticalScrollIndicator = true
            self.scrollView.showsHorizontalScrollIndicator = false
            self.scrollView.delaysContentTouches = false
            self.scrollView.canCancelContentTouches = true
            self.scrollView.contentInsetAdjustmentBehavior = .never
            self.scrollView.alwaysBounceVertical = true
            self.addSubview(self.scrollView)
            let tap = UITapGestureRecognizer(target: self, action: #selector(self.backgroundTapped(_:)))
            tap.cancelsTouchesInView = false
            self.scrollView.addGestureRecognizer(tap)

            self.scrollView.addSubview(self.iconView)
            self.scrollView.addSubview(self.subtitleView)
            self.sectionHeader.font = Font.regular(13.0)
            self.scrollView.addSubview(self.sectionHeader)

            self.card.layer.cornerRadius = 26.0
            self.card.layer.cornerCurve = .continuous
            self.card.clipsToBounds = true
            self.scrollView.addSubview(self.card)
            for layer in [self.pathTrack, self.path] {
                layer.fillColor = UIColor.clear.cgColor
                layer.lineCap = .round
                layer.lineWidth = 2.5
                layer.contentsScale = UIScreenScale * 2.0
                self.card.layer.addSublayer(layer)
            }
            self.pathTrack.lineDashPattern = [2.0, 6.0]
            self.path.strokeColor = GroupRulesColors.bottom.withAlphaComponent(0.55).cgColor
            self.addRow.addTarget(self, action: #selector(self.addPressed), for: .touchUpInside)
            self.card.addSubview(self.addRow)

            self.footer.font = Font.regular(13.0)
            self.footer.numberOfLines = 0
            self.scrollView.addSubview(self.footer)

            self.toggleCard.layer.cornerRadius = 26.0
            self.toggleCard.layer.cornerCurve = .continuous
            self.toggleCard.clipsToBounds = true
            self.scrollView.addSubview(self.toggleCard)
            self.sealTile.backgroundColor = GroupRulesColors.seal
            self.sealTile.layer.cornerRadius = 7.0
            self.sealTile.layer.cornerCurve = .continuous
            self.sealTile.isUserInteractionEnabled = false
            self.toggleCard.addSubview(self.sealTile)
            self.sealCheck.fillColor = UIColor.clear.cgColor
            self.sealCheck.strokeColor = UIColor.white.cgColor
            self.sealCheck.lineWidth = 2.6
            self.sealCheck.lineCap = .round
            self.sealCheck.lineJoin = .round
            self.sealCheck.contentsScale = UIScreenScale * 2.0
            self.sealTile.layer.addSublayer(self.sealCheck)
            self.toggleTitle.font = ruleFont
            self.toggleTitle.isAccessibilityElement = false
            self.toggleCard.addSubview(self.toggleTitle)
            self.toggleSwitch.addTarget(self, action: #selector(self.toggleChanged), for: .valueChanged)
            self.toggleCard.addSubview(self.toggleSwitch)
            self.toggleFooter.font = Font.regular(13.0)
            self.toggleFooter.numberOfLines = 0
            self.scrollView.addSubview(self.toggleFooter)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: State

        /// The rules as they would be saved: written ones only, in order.
        private var currentRules: GroupRules? {
            let texts = self.rows.map { $0.trimmedText }.filter { !$0.isEmpty }
            if texts.isEmpty {
                return nil
            }
            return GroupRules(rules: texts, requiresAcceptance: self.requiresAcceptance)
        }

        private var hasChanges: Bool {
            return self.currentRules != self.component?.initialRules
        }

        /// Whether leaving now loses nothing (no changes, or they are saved).
        var canLeaveWithoutAsking: Bool {
            // While saving, leaving is fine: the save goes on.
            return !self.hasChanges || self.didSave || self.isSaving
        }

        /// How much room the description would have left with these rules (below zero: over the limit).
        private var roomLeft: Int {
            guard let component = self.component, let environment = self.environment else {
                return GroupRules.maxDescriptionLength
            }
            let about = GroupRules.about(text: component.descriptionText, rules: self.currentRules, header: component.blockHeader ?? environment.strings.GroupRules_Header)
            return GroupRules.maxDescriptionLength - GroupRules.length(of: about)
        }

        private func makeRow(text: String) -> GroupRulesEditorRuleRow {
            let row = GroupRulesEditorRuleRow(id: self.nextRowId, text: text)
            self.nextRowId += 1
            row.changed = { [weak self] row in
                self?.rowChanged(row)
            }
            row.focusChanged = { [weak self] row, focused in
                self?.rowFocusChanged(row, focused: focused)
            }
            row.deleteRequested = { [weak self] row in
                self?.deleteRow(row)
            }
            return row
        }

        // MARK: Actions

        @objc private func backgroundTapped(_ recognizer: UITapGestureRecognizer) {
            let point = recognizer.location(in: self.scrollView)
            for row in self.rows where row.textView.isFirstResponder {
                if !row.convert(row.bounds, to: self.scrollView).contains(point) {
                    row.textView.resignFirstResponder()
                }
            }
        }

        @objc private func addPressed() {
            guard let environment = self.environment, !self.isSaving, self.rows.count < GroupRules.maxRules else {
                return
            }
            // A rule still empty is written first.
            if let empty = self.rows.first(where: { $0.trimmedText.isEmpty }) {
                empty.textView.becomeFirstResponder()
                return
            }
            self.haptic.impact(.light)
            let row = self.makeRow(text: "")
            // It opens where Add Rule is, and Add Rule moves down below it.
            row.frame = CGRect(origin: self.addRow.frame.origin, size: CGSize(width: self.addRow.bounds.width, height: rowMinHeight))
            let _ = row.layout(width: row.bounds.width)
            self.card.insertSubview(row, belowSubview: self.addRow)
            self.rows.append(row)
            row.update(theme: environment.theme, strings: environment.strings, number: self.rows.count, animated: false)
            row.animateFromPlus(accentColor: environment.theme.list.itemAccentColor)
            self.addRow.animateNewPlus(delay: 0.16)
            self.focusedRowId = row.id
            self.state?.updated(transition: .spring(duration: 0.5))
            row.textView.becomeFirstResponder()
        }

        private func rowChanged(_ row: GroupRulesEditorRuleRow) {
            guard !self.isUpdating else {
                return
            }
            let height = row.bounds.height
            let width = row.bounds.width
            let updatedHeight = row.layout(width: width)
            self.state?.updated(transition: updatedHeight != height ? .spring(duration: 0.4) : .immediate)
        }

        private func rowFocusChanged(_ row: GroupRulesEditorRuleRow, focused: Bool) {
            if focused {
                self.focusedRowId = row.id
                self.scrollToFocusedRow(animated: true)
            } else {
                if self.focusedRowId == row.id {
                    self.focusedRowId = nil
                }
                // A row being taken out lays the rest out itself, with its animation.
                if row.isRemoving {
                    return
                }
                // A rule left empty goes away.
                if row.trimmedText.isEmpty && self.rows.contains(where: { $0 === row }) {
                    self.deleteRow(row)
                } else if !self.isUpdating {
                    self.state?.updated(transition: .immediate)
                }
            }
        }

        private func deleteRow(_ row: GroupRulesEditorRuleRow) {
            guard let index = self.rows.firstIndex(where: { $0 === row }), !self.isSaving else {
                return
            }
            self.haptic.impact(.light)
            row.isRemoving = true
            self.rows.remove(at: index)
            if row.textView.isFirstResponder {
                row.textView.resignFirstResponder()
            }
            self.card.sendSubviewToBack(row)
            row.animateOut(completion: { [weak row] in
                row?.removeFromSuperview()
            })
            self.state?.updated(transition: .spring(duration: 0.5))
        }

        @objc private func toggleChanged() {
            guard !self.isSaving else {
                self.toggleSwitch.setOn(self.requiresAcceptance, animated: true)
                return
            }
            self.requiresAcceptance = self.toggleSwitch.isOn
            self.haptic.impact(.medium)
            if self.requiresAcceptance {
                // The seal stamps onto the scroll at the top, and its tile in the row stamps too.
                self.iconView.stampSeal(delay: 0.0)
                self.stampSealTile()
            } else {
                self.iconView.liftSeal()
                if !UIAccessibility.isReduceMotionEnabled {
                    rulesAddKeyframes(self.sealTile.layer, keyPath: "transform.scale", values: [1.0, 0.86, 1.0], keyTimes: [0.0, 0.4, 1.0], duration: 0.3, delay: 0.0)
                }
            }
            UIView.animate(withDuration: 0.25, animations: {
                self.sealTile.alpha = self.requiresAcceptance ? 1.0 : 0.45
            })
            self.state?.updated(transition: .easeInOut(duration: 0.25))
        }

        /// The tile drops onto the row large and turning, lands with a squash, and its check is drawn.
        private func stampSealTile() {
            guard !UIAccessibility.isReduceMotionEnabled else {
                return
            }
            rulesAddKeyframes(self.sealTile.layer, keyPath: "transform.scale", values: [1.0, 1.6, 0.82, 1.08, 1.0], keyTimes: [0.0, 0.25, 0.55, 0.8, 1.0], duration: 0.55, delay: 0.0)
            rulesAddKeyframes(self.sealTile.layer, keyPath: "transform.rotation.z", values: [0.0, -0.5, 0.1, 0.0], keyTimes: [0.0, 0.25, 0.6, 1.0], duration: 0.55, delay: 0.0)
            rulesAddKeyframes(self.sealCheck, keyPath: "strokeEnd", values: [0.0, 0.0, 1.0], keyTimes: [0.0, 0.45, 1.0], duration: 0.5, delay: 0.0, timing: .easeOut)
        }

        private func save() {
            guard let component = self.component, let environment = self.environment, !self.isSaving, self.hasChanges else {
                return
            }
            self.endEditing(true)
            let context = component.context
            let peerId = component.peerId
            let rules = self.currentRules
            let strings = environment.strings
            let blockHeader = component.blockHeader
            self.isSaving = true
            self.state?.updated(transition: .easeInOut(duration: 0.2))

            let failed: (String) -> Void = { [weak self] text in
                guard let self else {
                    return
                }
                self.isSaving = false
                self.state?.updated(transition: .easeInOut(duration: 0.2))
                self.haptic.error()
                self.presentAlert(text)
            }
            // The description as it is on the server now (another admin may have changed it), then written with the
            // rules at its end. The save goes on if the screen is left meanwhile.
            let _ = (GroupRulesEditorScreen.currentAbout(context: context, peerId: peerId)
            |> deliverOnMainQueue).startStandalone(next: { [weak self] currentAbout in
                let text = GroupRules.split(about: currentAbout).text
                // The block keeps the word it is headed with (whoever wrote it first, in their language).
                let header = GroupRules.header(about: currentAbout) ?? blockHeader ?? strings.GroupRules_Header
                let about = GroupRules.about(text: text, rules: rules, header: header)
                let over = GroupRules.length(of: about) - GroupRules.maxDescriptionLength
                if over > 0 {
                    failed(strings.GroupRules_TooLong("\(over)").string)
                    self?.shakeCard()
                    return
                }
                let _ = (GroupRulesEditorScreen.updateAbout(context: context, peerId: peerId, about: about)
                |> deliverOnMainQueue).startStandalone(error: { _ in
                    failed(strings.GroupRules_SaveError)
                }, completed: { [weak self] in
                    guard let self else {
                        return
                    }
                    self.didSave = true
                    self.haptic.success()
                    (self.environment?.controller() as? GroupRulesEditorScreen)?.dismiss()
                })
            }, error: { _ in
                failed(strings.GroupRules_SaveError)
            })
        }

        private func shakeCard() {
            guard !UIAccessibility.isReduceMotionEnabled else {
                return
            }
            rulesAddKeyframes(self.card.layer, keyPath: "transform.translation.x", values: [0.0, -10.0, 9.0, -6.0, 4.0, -2.0, 0.0], keyTimes: [0.0, 0.15, 0.3, 0.48, 0.66, 0.84, 1.0], duration: 0.45, delay: 0.0)
        }

        private func presentAlert(_ text: String) {
            guard let component = self.component, let controller = self.environment?.controller() else {
                return
            }
            let presentationData = component.context.sharedContext.currentPresentationData.with { $0 }
            controller.present(textAlertController(context: component.context, updatedPresentationData: nil, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
        }

        // MARK: Scrolling

        /// How much of the bottom of the screen is covered (by the keyboard or the button).
        private var bottomObscured: CGFloat = 0.0

        private func scrollToFocusedRow(animated: Bool) {
            guard let focusedRowId = self.focusedRowId, let row = self.rows.first(where: { $0.id == focusedRowId }), let environment = self.environment else {
                return
            }
            let frame = row.convert(row.bounds, to: self.scrollView).insetBy(dx: 0.0, dy: -12.0)
            let visibleHeight = self.scrollView.bounds.height - self.bottomObscured
            let top = self.scrollView.contentOffset.y + environment.navigationHeight
            let bottom = self.scrollView.contentOffset.y + visibleHeight
            var offset = self.scrollView.contentOffset.y
            if frame.maxY > bottom {
                offset += frame.maxY - bottom
            } else if frame.minY < top {
                offset -= top - frame.minY
            }
            let maxOffset = max(0.0, self.scrollView.contentSize.height + self.scrollView.contentInset.bottom - self.scrollView.bounds.height)
            offset = max(0.0, min(offset, maxOffset))
            if abs(offset - self.scrollView.contentOffset.y) > 0.5 {
                self.scrollView.setContentOffset(CGPoint(x: 0.0, y: offset), animated: animated)
            }
        }

        // MARK: Layout

        func update(component: GroupRulesEditorScreenComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: ComponentTransition) -> CGSize {
            self.isUpdating = true
            defer {
                self.isUpdating = false
            }
            let environment = environment[EnvironmentType.self].value
            let themeUpdated = self.environment?.theme !== environment.theme
            if self.component == nil {
                if let initial = component.initialRules {
                    for rule in initial.rules {
                        let row = self.makeRow(text: rule)
                        self.card.insertSubview(row, belowSubview: self.addRow)
                        self.rows.append(row)
                    }
                    self.requiresAcceptance = initial.requiresAcceptance
                }
                self.toggleSwitch.isOn = self.requiresAcceptance
                self.iconView.isSealed = self.requiresAcceptance
                self.sealTile.alpha = self.requiresAcceptance ? 1.0 : 0.45
            }
            self.component = component
            self.environment = environment
            self.state = state
            let theme = environment.theme
            let strings = environment.strings
            if themeUpdated {
                self.backgroundColor = theme.list.blocksBackgroundColor
                self.sectionHeader.textColor = theme.list.freeTextColor
                self.card.backgroundColor = theme.list.itemBlocksBackgroundColor
                self.toggleCard.backgroundColor = theme.list.itemBlocksBackgroundColor
                self.pathTrack.strokeColor = theme.list.itemSecondaryTextColor.withAlphaComponent(0.2).cgColor
                self.toggleTitle.textColor = theme.list.itemPrimaryTextColor
                self.toggleSwitch.onTintColor = theme.list.itemSwitchColors.positiveColor
                self.toggleFooter.textColor = theme.list.freeTextColor
            }

            // The title in the navigation bar.
            let navigationTitleSize = self.navigationTitle.update(
                transition: transition,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: strings.GroupRules_Title, font: Font.semibold(17.0), textColor: theme.rootController.navigationBar.primaryTextColor)),
                    horizontalAlignment: .center
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width, height: 100.0)
            )
            let navigationTitleFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - navigationTitleSize.width) / 2.0), y: environment.statusBarHeight + floor((environment.navigationHeight - environment.statusBarHeight - navigationTitleSize.height) / 2.0)), size: navigationTitleSize)
            if let navigationTitleView = self.navigationTitle.view {
                if navigationTitleView.superview == nil, let navigationBar = environment.controller()?.navigationBar {
                    navigationBar.view.addSubview(navigationTitleView)
                }
                transition.setFrame(view: navigationTitleView, frame: navigationTitleFrame)
            }

            let sideInset: CGFloat = 16.0 + environment.safeInsets.left
            let rightSideInset: CGFloat = 16.0 + environment.safeInsets.right
            let contentWidth = availableSize.width - sideInset - rightSideInset
            let centerX = sideInset + contentWidth * 0.5
            var y: CGFloat = environment.navigationHeight + 10.0

            // The scroll and what the rules are for.
            let iconSide: CGFloat = 92.0
            transition.setFrame(view: self.iconView, frame: CGRect(x: floor(centerX - iconSide * 0.5), y: y, width: iconSide, height: iconSide))
            y += iconSide + 16.0
            let subtitleSize = self.subtitleView.update(text: NSAttributedString(string: strings.GroupRules_EditorText(component.groupTitle).string, attributes: [.font: Font.regular(15.0), .foregroundColor: theme.list.freeTextColor]), width: contentWidth - 24.0, maxLines: 4, alignment: .center)
            transition.setFrame(view: self.subtitleView, frame: CGRect(x: floor(centerX - subtitleSize.width * 0.5), y: y, width: subtitleSize.width, height: subtitleSize.height))
            self.subtitleView.isAccessibilityElement = true
            self.subtitleView.accessibilityLabel = strings.GroupRules_EditorText(component.groupTitle).string
            y += subtitleSize.height + 26.0

            // The rules.
            self.sectionHeader.text = strings.GroupRules_Header.uppercased()
            self.sectionHeader.sizeToFit()
            transition.setFrame(view: self.sectionHeader, frame: CGRect(x: sideInset + 16.0, y: y, width: contentWidth - 32.0, height: self.sectionHeader.bounds.height))
            y += self.sectionHeader.bounds.height + 7.0

            var rowY: CGFloat = 0.0
            var badgeCenters: [CGPoint] = []
            for (index, row) in self.rows.enumerated() {
                row.update(theme: theme, strings: strings, number: index + 1, animated: !transition.animation.isImmediate)
                let height = row.layout(width: contentWidth)
                transition.setFrame(view: row, frame: CGRect(x: 0.0, y: rowY, width: contentWidth, height: height))
                badgeCenters.append(CGPoint(x: 16.0 + badgeSide * 0.5, y: rowY + rowMinHeight * 0.5))
                rowY += height
            }
            let canAdd = self.rows.count < GroupRules.maxRules
            self.addRow.update(theme: theme, strings: strings, width: contentWidth)
            transition.setFrame(view: self.addRow, frame: CGRect(x: 0.0, y: rowY, width: contentWidth, height: rowMinHeight))
            transition.setAlpha(view: self.addRow, alpha: canAdd ? 1.0 : 0.0)
            self.addRow.isUserInteractionEnabled = canAdd
            if canAdd {
                rowY += rowMinHeight
            }
            // The last rule's separator only when Add Rule follows it.
            for (index, row) in self.rows.enumerated() {
                row.separator.isHidden = index == self.rows.count - 1 && !canAdd
            }

            // The path from the first rule's number to the last one's.
            let pathShape = UIBezierPath()
            if let first = badgeCenters.first, let last = badgeCenters.last {
                pathShape.move(to: first)
                pathShape.addLine(to: last)
            }
            for layer in [self.pathTrack, self.path] {
                layer.frame = CGRect(origin: CGPoint(), size: CGSize(width: contentWidth, height: 2000.0))
                transition.setShapeLayerPath(layer: layer, path: pathShape.cgPath)
            }
            let cardFrame = CGRect(x: sideInset, y: y, width: contentWidth, height: max(rowY, 1.0))
            transition.setFrame(view: self.card, frame: cardFrame)
            y += cardFrame.height + 7.0

            // The footer: what the rules are, and the room the description has left when it gets short.
            let room = self.roomLeft
            var footerText = strings.GroupRules_EditorFooter
            var footerColor = theme.list.freeTextColor
            if room < 0 {
                footerText = strings.GroupRules_TooLong("\(-room)").string
                footerColor = theme.list.itemDestructiveColor
            } else if room <= 40 {
                footerText += " " + strings.GroupRules_RoomLeft("\(room)").string
            }
            self.footer.text = footerText
            self.footer.textColor = footerColor
            let footerSize = self.footer.sizeThatFits(CGSize(width: contentWidth - 32.0, height: .greatestFiniteMagnitude))
            transition.setFrame(view: self.footer, frame: CGRect(x: sideInset + 16.0, y: y, width: contentWidth - 32.0, height: ceil(footerSize.height)))
            y += ceil(footerSize.height) + 26.0

            // Ask to Accept.
            self.toggleTitle.text = strings.GroupRules_AskToAccept
            self.toggleSwitch.accessibilityLabel = strings.GroupRules_AskToAccept
            let toggleHeight: CGFloat = rowMinHeight
            let tileSide: CGFloat = 30.0
            self.sealTile.bounds = CGRect(origin: CGPoint(), size: CGSize(width: tileSide, height: tileSide))
            self.sealTile.center = CGPoint(x: 16.0 + tileSide * 0.5, y: toggleHeight * 0.5)
            let check = UIBezierPath()
            check.move(to: CGPoint(x: tileSide * 0.28, y: tileSide * 0.52))
            check.addLine(to: CGPoint(x: tileSide * 0.44, y: tileSide * 0.67))
            check.addLine(to: CGPoint(x: tileSide * 0.72, y: tileSide * 0.36))
            self.sealCheck.frame = self.sealTile.bounds
            self.sealCheck.path = check.cgPath
            let switchSize = self.toggleSwitch.sizeThatFits(CGSize(width: 100.0, height: 100.0))
            self.toggleSwitch.frame = CGRect(x: contentWidth - 16.0 - switchSize.width, y: floor((toggleHeight - switchSize.height) * 0.5), width: switchSize.width, height: switchSize.height)
            let lineHeight = ceil(ruleFont.lineHeight)
            self.toggleTitle.frame = CGRect(x: 16.0 + tileSide + 16.0, y: floor((toggleHeight - lineHeight) * 0.5), width: max(1.0, self.toggleSwitch.frame.minX - 62.0 - 8.0), height: lineHeight)
            self.toggleSwitch.isEnabled = !self.rows.isEmpty && !self.isSaving
            // Nothing is changed while it is being saved.
            self.card.isUserInteractionEnabled = !self.isSaving
            transition.setFrame(view: self.toggleCard, frame: CGRect(x: sideInset, y: y, width: contentWidth, height: toggleHeight))
            y += toggleHeight + 7.0
            self.toggleFooter.text = strings.GroupRules_AskToAcceptFooter
            let toggleFooterSize = self.toggleFooter.sizeThatFits(CGSize(width: contentWidth - 32.0, height: .greatestFiniteMagnitude))
            transition.setFrame(view: self.toggleFooter, frame: CGRect(x: sideInset + 16.0, y: y, width: contentWidth - 32.0, height: ceil(toggleFooterSize.height)))
            y += ceil(toggleFooterSize.height) + 24.0

            // Save, at the bottom.
            let buttonInsets = ContainerViewLayout.concentricInsets(bottomInset: environment.safeInsets.bottom, innerDiameter: 52.0, sideInset: 30.0)
            let buttonSize = self.saveButton.update(
                transition: transition,
                component: AnyComponent(ButtonComponent(
                    background: ButtonComponent.Background(
                        style: .glass,
                        color: GroupRulesColors.bottom,
                        foreground: .white,
                        pressedColor: GroupRulesColors.bottom.withMultipliedAlpha(0.9),
                        cornerRadius: 26.0
                    ),
                    content: AnyComponentWithIdentity(id: "save", component: AnyComponent(Text(
                        text: strings.GroupRules_Save,
                        font: Font.semibold(17.0),
                        color: .white
                    ))),
                    isEnabled: self.hasChanges && room >= 0,
                    displaysProgress: self.isSaving,
                    action: { [weak self] in
                        self?.save()
                    }
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width - buttonInsets.left - buttonInsets.right, height: 52.0)
            )
            // It stays under the keyboard while a rule is written (the keyboard's Done ends the writing).
            let buttonFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - buttonSize.width) * 0.5), y: availableSize.height - buttonInsets.bottom - buttonSize.height), size: buttonSize)
            if let buttonView = self.saveButton.view {
                if buttonView.superview == nil {
                    self.addSubview(buttonView)
                }
                transition.setFrame(view: buttonView, frame: buttonFrame)
            }
            self.bottomObscured = max(environment.inputHeight, availableSize.height - buttonFrame.minY) + 12.0

            let contentSize = CGSize(width: availableSize.width, height: y)
            if self.scrollView.frame != CGRect(origin: CGPoint(), size: availableSize) {
                self.scrollView.frame = CGRect(origin: CGPoint(), size: availableSize)
            }
            if self.scrollView.contentSize != contentSize {
                self.scrollView.contentSize = contentSize
            }
            self.scrollView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: self.bottomObscured, right: 0.0)
            self.scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(top: environment.navigationHeight, left: 0.0, bottom: self.bottomObscured, right: 0.0)

            if environment.inputHeight != self.lastInputHeight {
                self.lastInputHeight = environment.inputHeight
                DispatchQueue.main.async { [weak self] in
                    self?.scrollToFocusedRow(animated: true)
                }
            }

            if !self.didAppear {
                self.didAppear = true
                self.animateIn()
            }
            return availableSize
        }

        /// The screen comes in part by part: the scroll unrolls, the text writes itself, then the card rises and its
        /// rules light up one after another along the path, then the rest.
        private func animateIn() {
            guard !UIAccessibility.isReduceMotionEnabled else {
                return
            }
            self.iconView.animateUnroll(delay: 0.06)
            let _ = self.subtitleView.animateLettersIn(delay: 0.24, stagger: 0.007, offset: 6.0)
            rulesAnimateRiseIn(self.sectionHeader.layer, delay: 0.3, offset: 10.0, scale: 1.0, blur: 4.0)
            rulesAnimateRiseIn(self.card.layer, delay: 0.34, offset: 22.0, scale: 0.97, blur: 6.0)
            let start = 0.46
            let step = 0.09
            let count = self.rows.count
            if count > 1 {
                rulesAddKeyframes(self.path, keyPath: "strokeEnd", values: [0.0, 1.0], keyTimes: [0.0, 1.0], duration: step * Double(count - 1), delay: start, timing: .linear)
            }
            for (index, row) in self.rows.enumerated() {
                let reach = start + Double(index) * step
                rulesAddKeyframes(row.badge.layer, keyPath: "opacity", values: [0.0, 1.0], keyTimes: [0.0, 1.0], duration: 0.1, delay: reach)
                rulesAddKeyframes(row.badge.layer, keyPath: "transform.scale", values: [0.2, 1.3, 0.92, 1.0], keyTimes: [0.0, 0.4, 0.72, 1.0], duration: 0.5, delay: reach)
                rulesAddKeyframes(row.badge.layer, keyPath: "transform.rotation.z", values: [-1.2, 0.15, 0.0], keyTimes: [0.0, 0.5, 1.0], duration: 0.5, delay: reach)
                rulesAnimateRiseIn(row.textView.layer, delay: reach + 0.05, offset: 0.0, scale: 1.0, blur: 5.0)
                rulesAddKeyframes(row.textView.layer, keyPath: "transform.translation.x", values: [-12.0, 0.0], keyTimes: [0.0, 1.0], duration: 0.4, delay: reach + 0.05, timing: .easeOut)
                rulesAnimateRiseIn(row.deleteButton.layer, delay: reach + 0.1, offset: 0.0, scale: 0.5, blur: 0.0)
            }
            let addDelay = start + Double(count) * step
            rulesAddKeyframes(self.addRow.plusBadge.layer, keyPath: "transform.scale", values: [0.0, 1.2, 0.95, 1.0], keyTimes: [0.0, 0.45, 0.75, 1.0], duration: 0.5, delay: addDelay)
            rulesAnimateRiseIn(self.addRow.titleLabel2.layer, delay: addDelay + 0.05, offset: 0.0, scale: 1.0, blur: 5.0)
            rulesAnimateRiseIn(self.footer.layer, delay: addDelay + 0.08, offset: 10.0, scale: 1.0, blur: 4.0)
            rulesAnimateRiseIn(self.toggleCard.layer, delay: addDelay + 0.12, offset: 18.0, scale: 0.97, blur: 6.0)
            rulesAnimateRiseIn(self.toggleFooter.layer, delay: addDelay + 0.18, offset: 10.0, scale: 1.0, blur: 4.0)
            if let buttonView = self.saveButton.view {
                rulesAnimateRiseIn(buttonView.layer, delay: addDelay + 0.2, offset: 26.0, scale: 0.9, blur: 8.0)
            }
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

enum GroupRulesEditorError {
    case generic
}

/// A group's rules, for its admins: written one by one, and whether new members have to accept them. They are saved at
/// the end of the group's description.
public final class GroupRulesEditorScreen: ViewControllerComponentContainer {
    public init(context: AccountContext, peerId: EnginePeer.Id, groupTitle: String, about: String?) {
        let (text, rules) = GroupRules.split(about: about)
        super.init(context: context, component: GroupRulesEditorScreenComponent(
            context: context,
            peerId: peerId,
            groupTitle: groupTitle,
            descriptionText: text,
            initialRules: rules,
            blockHeader: GroupRules.header(about: about)
        ), navigationBarAppearance: .default, theme: .default, updatedPresentationData: nil)

        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.title = ""
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)

        // Leaving with rules not saved asks first.
        self.attemptNavigation = { [weak self] action in
            guard let self, let view = self.node.hostView.componentView as? GroupRulesEditorScreenComponent.View, !view.canLeaveWithoutAsking else {
                return true
            }
            let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
            self.present(textAlertController(context: context, title: strings.GroupRules_DiscardTitle, text: strings.GroupRules_DiscardText, actions: [
                TextAlertAction(type: .genericAction, title: strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: strings.GroupRules_DiscardAction, action: {
                    action()
                })
            ]), in: .window(.root))
            return false
        }
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The group's description as it is on the server now: the group is fetched again first, then read. Fails if it
    /// cannot be learned within ten seconds.
    static func currentAbout(context: AccountContext, peerId: EnginePeer.Id) -> Signal<String?, GroupRulesEditorError> {
        return context.engine.peers.fetchAndUpdateCachedPeerData(peerId: peerId)
        |> take(1)
        |> castError(GroupRulesEditorError.self)
        |> mapToSignal { _ -> Signal<String?, GroupRulesEditorError> in
            return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.AboutText(id: peerId))
            |> castError(GroupRulesEditorError.self)
            |> mapToSignal { about -> Signal<String?, GroupRulesEditorError> in
                if case let .known(text) = about {
                    return .single(text)
                }
                return .fail(.generic)
            }
        }
        |> timeout(10.0, queue: Queue.mainQueue(), alternate: .fail(.generic))
    }

    /// Writes the description (with or without the rules at its end).
    static func updateAbout(context: AccountContext, peerId: EnginePeer.Id, about: String) -> Signal<Void, UpdatePeerDescriptionError> {
        return context.engine.peers.updatePeerDescription(peerId: peerId, description: about.isEmpty ? nil : about)
    }

    override public func preferredContentSizeForLayout(_ layout: ContainerViewLayout) -> CGSize? {
        guard layout.metrics.widthClass == .regular else {
            return nil
        }
        return CGSize(width: min(480.0, layout.size.width - 20.0), height: min(layout.size.width, layout.size.height) - 88.0)
    }
}
