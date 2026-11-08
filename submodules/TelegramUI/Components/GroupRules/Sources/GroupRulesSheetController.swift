import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData

/// A group's rules, shown to someone who joins it: they come in one by one along a path, and the button accepts them.
/// Swiping the sheet down (or tapping outside it) closes it without accepting.
public final class GroupRulesSheetController: ViewController {
    private let presentationData: PresentationData
    private let text: String
    private let rules: GroupRules
    private let acceptTitle: String
    private let isSeenBefore: Bool
    /// Called once, when it has gone: whether the rules were accepted.
    private let completion: (Bool) -> Void

    private var sheetView: GroupRulesSheetView {
        return self.displayNode.view as! GroupRulesSheetView
    }

    /// `isSeenBefore`: the rules were shown and closed before, they come in quicker this time.
    public init(presentationData: PresentationData, text: String, rules: GroupRules, acceptTitle: String, isSeenBefore: Bool = false, completion: @escaping (Bool) -> Void) {
        self.presentationData = presentationData
        self.text = text
        self.rules = rules
        self.acceptTitle = acceptTitle
        self.isSeenBefore = isSeenBefore
        self.completion = completion
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Ignore
        self.blocksBackgroundWhenInOverlay = true
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadDisplayNode() {
        let presentationData = self.presentationData
        let text = self.text
        let rules = self.rules
        let acceptTitle = self.acceptTitle
        let isSeenBefore = self.isSeenBefore
        self.displayNode = ASDisplayNode(viewBlock: {
            return GroupRulesSheetView(presentationData: presentationData, text: text, rules: rules, acceptTitle: acceptTitle, isSeenBefore: isSeenBefore)
        }, didLoad: nil)
        self.displayNodeDidLoad()
        self.sheetView.finished = { [weak self] accepted in
            guard let self else {
                return
            }
            self.completion(accepted)
            self.dismiss()
        }
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.sheetView.update(layout: layout)
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.sheetView.animateIn()
    }
}

/// One rule in the sheet: its number on the path and its text.
private final class GroupRulesRuleRow {
    let badge = UIView()
    let numberLabel = UILabel()
    let glow = UIView()
    let textView = RulesTextView()
}

/// Lets the sheet's pan begin only when the sheet allows it, alongside the list's own scrolling.
private final class GroupRulesSheetPanDelegate: NSObject, UIGestureRecognizerDelegate {
    var shouldBegin: ((UIPanGestureRecognizer) -> Bool)?
    weak var scrollView: UIScrollView?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }
        return self.shouldBegin?(pan) ?? true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return otherGestureRecognizer === self.scrollView?.panGestureRecognizer
    }
}

final class GroupRulesSheetView: UIView, UIScrollViewDelegate {
    private let presentationData: PresentationData
    private let text: String
    private let rules: GroupRules
    private let acceptTitle: String
    private let isSeenBefore: Bool

    var finished: ((Bool) -> Void)?

    private let dimView = UIView()
    private let sheet = UIView()
    /// What is above the button, scrolling when it is taller than the screen allows.
    private let scrollView = UIScrollView()
    /// The list fades out above the button while there is more of it below.
    private let bottomFade = CAGradientLayer()
    /// And under the grabber once it is scrolled.
    private let topFade = CAGradientLayer()
    private let panDelegate = GroupRulesSheetPanDelegate()
    private var panMovesSheet = false
    private let grabber = UIView()
    private let iconView = GroupRulesIconView()
    private let titleView = RulesTextView()
    private let subtitleView = RulesTextView()
    private let path = CAShapeLayer()
    private let pathTrack = CAShapeLayer()
    private var rows: [GroupRulesRuleRow] = []
    private let noteView = RulesTextView()
    private let button = HighlightTrackingButton()
    private let buttonBackground = CAGradientLayer()
    private let buttonTitle = UILabel()
    private let buttonCheck = CAShapeLayer()

    private var sheetHeight: CGFloat = 0.0
    private var didAnimateIn = false
    private var isFinishing = false

    init(presentationData: PresentationData, text: String, rules: GroupRules, acceptTitle: String, isSeenBefore: Bool) {
        self.presentationData = presentationData
        self.text = text
        self.rules = rules
        self.acceptTitle = acceptTitle
        self.isSeenBefore = isSeenBefore
        super.init(frame: CGRect())

        let theme = presentationData.theme
        self.dimView.backgroundColor = UIColor(white: 0.0, alpha: 0.45)
        self.dimView.alpha = 0.0
        self.addSubview(self.dimView)
        self.dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dimTapped)))

        self.sheet.backgroundColor = theme.actionSheet.opaqueItemBackgroundColor
        self.sheet.layer.cornerRadius = 30.0
        if #available(iOS 13.0, *) {
            self.sheet.layer.cornerCurve = .continuous
        }
        self.sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        self.sheet.clipsToBounds = true
        self.addSubview(self.sheet)

        self.scrollView.showsHorizontalScrollIndicator = false
        self.scrollView.alwaysBounceVertical = false
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.scrollView.delaysContentTouches = false
        self.sheet.addSubview(self.scrollView)
        self.scrollView.delegate = self
        let sheetColor = theme.actionSheet.opaqueItemBackgroundColor
        self.bottomFade.colors = [sheetColor.withAlphaComponent(0.0).cgColor, sheetColor.cgColor]
        self.bottomFade.opacity = 0.0
        self.sheet.layer.addSublayer(self.bottomFade)
        self.topFade.colors = [sheetColor.cgColor, sheetColor.withAlphaComponent(0.0).cgColor]
        self.topFade.opacity = 0.0
        self.sheet.layer.addSublayer(self.topFade)
        self.grabber.backgroundColor = theme.actionSheet.secondaryTextColor.withAlphaComponent(0.35)
        self.grabber.layer.cornerRadius = 2.5
        self.sheet.addSubview(self.grabber)
        self.scrollView.addSubview(self.iconView)
        self.scrollView.addSubview(self.titleView)
        self.scrollView.addSubview(self.subtitleView)

        for layer in [self.pathTrack, self.path] {
            layer.fillColor = UIColor.clear.cgColor
            layer.lineCap = .round
            layer.lineWidth = 2.5
            layer.contentsScale = UIScreenScale * 2.0
            self.scrollView.layer.addSublayer(layer)
        }
        self.pathTrack.strokeColor = theme.actionSheet.secondaryTextColor.withAlphaComponent(0.15).cgColor
        self.pathTrack.lineDashPattern = [2.0, 6.0]
        self.path.strokeColor = GroupRulesColors.bottom.cgColor

        for (index, _) in rules.rules.enumerated() {
            let row = GroupRulesRuleRow()
            row.glow.backgroundColor = GroupRulesColors.top.withAlphaComponent(0.35)
            row.glow.alpha = 0.0
            self.scrollView.addSubview(row.glow)
            row.badge.backgroundColor = GroupRulesColors.bottom
            row.badge.layer.cornerRadius = 14.0
            self.scrollView.addSubview(row.badge)
            row.numberLabel.text = "\(index + 1)"
            row.numberLabel.font = Font.with(size: 15.0, design: .round, weight: .bold)
            row.numberLabel.textColor = .white
            row.numberLabel.textAlignment = .center
            row.badge.addSubview(row.numberLabel)
            self.scrollView.addSubview(row.textView)
            self.rows.append(row)
        }

        self.scrollView.addSubview(self.noteView)
        self.buttonBackground.colors = [theme.list.itemAccentColor.withMultipliedBrightnessBy(1.08).cgColor, theme.list.itemAccentColor.cgColor]
        self.buttonBackground.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.buttonBackground.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.button.layer.addSublayer(self.buttonBackground)
        self.buttonTitle.text = acceptTitle
        self.buttonTitle.font = Font.semibold(17.0)
        self.buttonTitle.textColor = .white
        self.buttonTitle.textAlignment = .center
        self.button.addSubview(self.buttonTitle)
        self.buttonCheck.fillColor = UIColor.clear.cgColor
        self.buttonCheck.strokeColor = UIColor.white.cgColor
        self.buttonCheck.lineWidth = 3.0
        self.buttonCheck.lineCap = .round
        self.buttonCheck.lineJoin = .round
        self.buttonCheck.strokeEnd = 0.0
        self.buttonCheck.contentsScale = UIScreenScale * 2.0
        self.button.layer.addSublayer(self.buttonCheck)
        self.button.highligthedChanged = { [weak self] highlighted in
            guard let self else {
                return
            }
            let scale: CGFloat = highlighted ? 0.96 : 1.0
            UIView.animate(withDuration: highlighted ? 0.12 : 0.3, delay: 0.0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.0, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                self.button.transform = CGAffineTransform(scaleX: scale, y: scale)
            })
        }
        self.button.addTarget(self, action: #selector(self.acceptPressed), for: .touchUpInside)
        self.sheet.addSubview(self.button)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(self.panned(_:)))
        self.panDelegate.scrollView = self.scrollView
        self.panDelegate.shouldBegin = { [weak self] pan in
            guard let self, !self.isFinishing else {
                return false
            }
            let velocity = pan.velocity(in: self)
            return abs(velocity.y) > abs(velocity.x)
        }
        pan.delegate = self.panDelegate
        self.sheet.addGestureRecognizer(pan)

        self.isAccessibilityElement = false
        self.accessibilityViewIsModal = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    func update(layout: ContainerViewLayout) {
        let theme = self.presentationData.theme
        let strings = self.presentationData.strings
        let size = layout.size
        let width = min(size.width, 520.0)
        let sheetX = floor((size.width - width) * 0.5)
        // More room at the sides only where the sheet reaches under the safe area (not in a narrow card on a wide screen).
        let safeOverlap = max(0.0, layout.safeInsets.left - sheetX, layout.safeInsets.right - (size.width - sheetX - width))
        let sideInset: CGFloat = 24.0 + safeOverlap
        let contentWidth = width - sideInset * 2.0

        self.dimView.frame = CGRect(origin: CGPoint(), size: size)

        self.grabber.frame = CGRect(x: floor((width - 36.0) * 0.5), y: 10.0, width: 36.0, height: 5.0)
        // The list scrolls below the grabber.
        let listTop: CGFloat = 24.0
        var y: CGFloat = 37.0 - listTop

        let iconSide: CGFloat = 78.0
        self.iconView.frame = CGRect(x: floor((width - iconSide) * 0.5), y: y, width: iconSide, height: iconSide)
        y = ceil(y + iconSide + 18.0)

        let titleSize = self.titleView.update(text: NSAttributedString(string: strings.GroupRules_Title, attributes: [.font: Font.with(size: 26.0, design: .round, weight: .bold), .foregroundColor: theme.actionSheet.primaryTextColor]), width: contentWidth, maxLines: 1, alignment: .center)
        self.titleView.frame = CGRect(x: floor((width - titleSize.width) * 0.5), y: y, width: titleSize.width, height: titleSize.height)
        y = ceil(y + titleSize.height + 8.0)

        let subtitleSize = self.subtitleView.update(text: NSAttributedString(string: self.text, attributes: [.font: Font.regular(15.0), .foregroundColor: theme.actionSheet.secondaryTextColor]), width: contentWidth - 12.0, maxLines: 3, alignment: .center)
        self.subtitleView.frame = CGRect(x: floor((width - subtitleSize.width) * 0.5), y: y, width: subtitleSize.width, height: subtitleSize.height)
        y = ceil(y + subtitleSize.height + 26.0)

        // The rules along a path: a badge with the number on the left, the text beside it.
        let badgeSide: CGFloat = 28.0
        let textX = sideInset + badgeSide + 14.0
        let textWidth = width - textX - sideInset
        var badgeCenters: [CGPoint] = []
        for row in self.rows {
            let index = badgeCenters.count
            let rule = self.rules.rules[index]
            let textSize = row.textView.update(text: NSAttributedString(string: rule, attributes: [.font: Font.regular(17.0), .foregroundColor: theme.actionSheet.primaryTextColor]), width: textWidth, maxLines: 20)
            let rowHeight = max(badgeSide, textSize.height)
            row.badge.frame = CGRect(x: sideInset, y: y + floor((min(rowHeight, 44.0) - badgeSide) * 0.5), width: badgeSide, height: badgeSide)
            row.numberLabel.frame = row.badge.bounds
            row.glow.frame = row.badge.frame.insetBy(dx: -8.0, dy: -8.0)
            row.glow.layer.cornerRadius = row.glow.bounds.width * 0.5
            row.textView.frame = CGRect(x: textX, y: y + floor((min(rowHeight, 44.0) - min(textSize.height, 44.0)) * 0.5), width: textSize.width, height: textSize.height)
            badgeCenters.append(CGPoint(x: row.badge.frame.midX, y: row.badge.frame.midY))
            y = ceil(y + rowHeight + 18.0)
        }
        if let first = badgeCenters.first, let last = badgeCenters.last {
            let pathShape = UIBezierPath()
            pathShape.move(to: first)
            pathShape.addLine(to: last)
            for layer in [self.pathTrack, self.path] {
                layer.frame = CGRect(origin: CGPoint(), size: CGSize(width: width, height: 2000.0))
                layer.path = pathShape.cgPath
            }
        }
        y = ceil(y + 4.0)

        let noteSize = self.noteView.update(text: NSAttributedString(string: strings.GroupRules_SheetNote, attributes: [.font: Font.regular(13.0), .foregroundColor: theme.actionSheet.secondaryTextColor]), width: contentWidth, maxLines: 2, alignment: .center)
        self.noteView.frame = CGRect(x: floor((width - noteSize.width) * 0.5), y: y, width: noteSize.width, height: noteSize.height)
        y = ceil(y + noteSize.height)

        // The button stays at the bottom; above it the rest scrolls when it does not fit under the status bar.
        let buttonHeight: CGFloat = 54.0
        let buttonArea = 14.0 + buttonHeight + ceil(max(16.0, layout.intrinsicInsets.bottom + 8.0))
        let topLimit = max(layout.statusBarHeight ?? 0.0, layout.safeInsets.top) + 12.0
        let contentHeight = y
        let scrollHeight = max(1.0, min(contentHeight, size.height - topLimit - buttonArea - listTop))
        self.scrollView.frame = CGRect(x: 0.0, y: listTop, width: width, height: scrollHeight)
        self.scrollView.contentSize = CGSize(width: width, height: contentHeight)
        self.scrollView.isScrollEnabled = contentHeight > scrollHeight + 0.5
        self.scrollView.showsVerticalScrollIndicator = self.scrollView.isScrollEnabled
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.bottomFade.frame = CGRect(x: 0.0, y: listTop + scrollHeight - 28.0, width: width, height: 28.0)
        self.topFade.frame = CGRect(x: 0.0, y: listTop, width: width, height: 18.0)
        CATransaction.commit()
        self.updateBottomFade()
        y = listTop + scrollHeight + 14.0
        self.button.frame = CGRect(x: sideInset, y: y, width: contentWidth, height: buttonHeight)
        self.buttonBackground.frame = self.button.bounds
        self.buttonBackground.cornerRadius = buttonHeight * 0.5
        self.buttonTitle.frame = self.button.bounds
        let check = UIBezierPath()
        let center = CGPoint(x: contentWidth * 0.5, y: buttonHeight * 0.5)
        check.move(to: CGPoint(x: center.x - 10.0, y: center.y + 1.0))
        check.addLine(to: CGPoint(x: center.x - 3.0, y: center.y + 8.0))
        check.addLine(to: CGPoint(x: center.x + 11.0, y: center.y - 7.0))
        self.buttonCheck.frame = self.button.bounds
        self.buttonCheck.path = check.cgPath
        y = listTop + scrollHeight + buttonArea

        self.sheetHeight = y
        self.sheet.bounds = CGRect(origin: CGPoint(), size: CGSize(width: width, height: y + 40.0))
        self.sheet.center = CGPoint(x: sheetX + width * 0.5, y: size.height - y + (y + 40.0) * 0.5)
        if !self.didAnimateIn {
            // Below the screen until it comes in.
            self.sheet.transform = CGAffineTransform(translationX: 0.0, y: y + 60.0)
        }
        self.accessibilityElements = [self.titleView, self.subtitleView] + self.rows.map { $0.textView } + [self.button]
        self.titleView.isAccessibilityElement = true
        self.titleView.accessibilityLabel = strings.GroupRules_Title
        self.titleView.accessibilityTraits = .header
        self.subtitleView.isAccessibilityElement = true
        self.subtitleView.accessibilityLabel = self.text
        for (index, row) in self.rows.enumerated() {
            row.textView.isAccessibilityElement = true
            row.textView.accessibilityLabel = "\(index + 1). \(self.rules.rules[index])"
        }
        self.button.accessibilityLabel = self.acceptTitle
    }

    // MARK: - Coming in

    /// The sheet rises with a spring, a little large, and its parts come in: the scroll unrolls, the title rises letter
    /// by letter, then the path grows down from rule to rule, each number lighting up as it is reached and its rule
    /// writing itself; last the note and the button, with light passing over it.
    func animateIn() {
        guard !self.didAnimateIn else {
            return
        }
        self.didAnimateIn = true
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: 0.3, animations: {
            self.dimView.alpha = 1.0
        })
        if reduceMotion {
            self.sheet.transform = .identity
            UIAccessibility.post(notification: .screenChanged, argument: self.titleView)
            return
        }
        UIView.animate(withDuration: 0.7, delay: 0.0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.0, options: [.allowUserInteraction], animations: {
            self.sheet.transform = .identity
        })
        rulesAddKeyframes(self.sheet.layer, keyPath: "transform.scale", values: [0.92, 1.025, 1.0], keyTimes: [0.0, 0.55, 1.0], duration: 0.7, delay: 0.0)

        self.iconView.animateUnroll(delay: 0.18)
        let titleEnd = self.titleView.animateLettersIn(delay: 0.42, stagger: 0.03, offset: 12.0)
        let _ = self.subtitleView.animateLettersIn(delay: 0.62, stagger: 0.008, offset: 6.0)

        // The rules, one after another along the path.
        // Seen before: the same coming in, at a quicker pace.
        let rulesStart = self.isSeenBefore ? 0.62 : max(0.95, min(titleEnd, 1.1))
        // A long list comes in quicker (the whole of it in about two and a half seconds).
        let count = self.rows.count
        let step = self.isSeenBefore ? 0.2 : (count > 5 ? max(0.22, 2.4 / Double(count)) : 0.48)
        if count > 1 {
            rulesAddKeyframes(self.path, keyPath: "strokeEnd", values: [0.0, 1.0], keyTimes: [0.0, 1.0], duration: step * Double(count - 1), delay: rulesStart, timing: .linear)
            rulesAddKeyframes(self.pathTrack, keyPath: "opacity", values: [0.0, 1.0], keyTimes: [0.0, 1.0], duration: 0.3, delay: rulesStart - 0.2)
        }
        var lastTextEnd = rulesStart
        for (index, row) in self.rows.enumerated() {
            let reach = rulesStart + Double(index) * step
            // The number lights up as the path reaches it: it pops up turning, and a glow pulses behind it.
            row.badge.alpha = 1.0
            rulesAddKeyframes(row.badge.layer, keyPath: "opacity", values: [0.0, 1.0], keyTimes: [0.0, 1.0], duration: 0.1, delay: reach)
            rulesAddKeyframes(row.badge.layer, keyPath: "transform.scale", values: [0.2, 1.35, 0.9, 1.05, 1.0], keyTimes: [0.0, 0.35, 0.6, 0.82, 1.0], duration: 0.55, delay: reach)
            rulesAddKeyframes(row.badge.layer, keyPath: "transform.rotation.z", values: [-1.4, 0.2, -0.06, 0.0], keyTimes: [0.0, 0.4, 0.75, 1.0], duration: 0.55, delay: reach)
            rulesAddKeyframes(row.numberLabel.layer, keyPath: "transform.scale", values: [0.3, 0.3, 1.2, 1.0], keyTimes: [0.0, 0.3, 0.7, 1.0], duration: 0.5, delay: reach)
            rulesAddKeyframes(row.glow.layer, keyPath: "opacity", values: [0.0, 1.0, 0.0], keyTimes: [0.0, 0.25, 1.0], duration: 0.8, delay: reach, timing: .easeOut)
            rulesAddKeyframes(row.glow.layer, keyPath: "transform.scale", values: [0.4, 1.0, 1.5], keyTimes: [0.0, 0.3, 1.0], duration: 0.8, delay: reach, timing: .easeOut)
            // Its rule writes itself, letter by letter.
            // A long rule writes itself quicker (in at most about 0.6 s).
            let ruleLength = max(1, self.rules.rules[index].count)
            let stagger = min(self.isSeenBefore ? 0.008 : 0.016, 0.6 / Double(ruleLength))
            let textEnd = row.textView.animateLettersIn(delay: reach + 0.14, stagger: stagger, offset: 8.0)
            lastTextEnd = max(lastTextEnd, textEnd)
        }
        let _ = self.noteView.animateLettersIn(delay: lastTextEnd - 0.1, stagger: 0.006, offset: 5.0)
        // The button rises in last, a little large, and light passes over it.
        let buttonDelay = lastTextEnd + 0.05
        // It cannot be pressed before it is there (a second tap on Join would land on it).
        self.button.isUserInteractionEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + buttonDelay + 0.15, execute: { [weak self] in
            self?.button.isUserInteractionEnabled = true
        })
        rulesAnimateRiseIn(self.button.layer, delay: buttonDelay, offset: 30.0, scale: 0.86, blur: 10.0)
        rulesAddKeyframes(self.button.layer, keyPath: "transform.scale", values: [0.86, 1.06, 0.98, 1.0], keyTimes: [0.0, 0.45, 0.75, 1.0], duration: 0.7, delay: buttonDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + buttonDelay + 0.45, execute: { [weak self] in
            guard let self else {
                return
            }
            rulesAnimateSheen(over: self.button, cornerRadius: self.button.bounds.height * 0.5, delay: 0.0, duration: 0.9, alpha: 0.45)
        })
        UIAccessibility.post(notification: .screenChanged, argument: self.titleView)
    }

    // MARK: - Scrolling

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.updateBottomFade()
    }

    private func updateBottomFade() {
        let scrollView = self.scrollView
        let atBottom = scrollView.contentOffset.y + scrollView.bounds.height >= scrollView.contentSize.height - 2.0
        let opacity: Float = scrollView.isScrollEnabled && !atBottom ? 1.0 : 0.0
        if self.bottomFade.opacity != opacity {
            self.bottomFade.opacity = opacity
        }
        let topOpacity: Float = scrollView.isScrollEnabled && scrollView.contentOffset.y > 1.0 ? 1.0 : 0.0
        if self.topFade.opacity != topOpacity {
            self.topFade.opacity = topOpacity
        }
    }

    // MARK: - Going

    @objc private func dimTapped() {
        self.finish(accepted: false, velocity: 0.0)
    }

    @objc private func acceptPressed() {
        guard !self.isFinishing else {
            return
        }
        self.isFinishing = true
        HapticFeedback().success()
        if UIAccessibility.isReduceMotionEnabled {
            self.slideOut(accepted: true, velocity: 0.0, delay: 0.0)
            return
        }
        // The title gives way to a check drawn on the button, the seal stamps onto the scroll, then the sheet goes.
        UIView.animate(withDuration: 0.18, animations: {
            self.buttonTitle.alpha = 0.0
            self.buttonTitle.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        })
        self.buttonBackground.colors = [GroupRulesColors.seal.withMultipliedBrightnessBy(1.08).cgColor, GroupRulesColors.seal.cgColor]
        self.buttonBackground.add({
            let animation = CABasicAnimation(keyPath: "colors")
            animation.duration = 0.3
            return animation
        }(), forKey: "colors")
        self.buttonCheck.strokeEnd = 1.0
        rulesAddKeyframes(self.buttonCheck, keyPath: "strokeEnd", values: [0.0, 1.0], keyTimes: [0.0, 1.0], duration: 0.32, delay: 0.1, timing: .easeOut)
        rulesAddKeyframes(self.button.layer, keyPath: "transform.scale", values: [1.0, 1.05, 1.0], keyTimes: [0.0, 0.5, 1.0], duration: 0.35, delay: 0.08)
        self.iconView.stampSeal(delay: 0.18)
        // Each number turns green in turn, bottom to top, as if signed.
        for (index, row) in self.rows.reversed().enumerated() {
            UIView.animate(withDuration: 0.2, delay: 0.25 + Double(index) * 0.05, options: [], animations: {
                row.badge.backgroundColor = GroupRulesColors.seal
            })
            rulesAddKeyframes(row.badge.layer, keyPath: "transform.scale", values: [1.0, 1.25, 1.0], keyTimes: [0.0, 0.4, 1.0], duration: 0.3, delay: 0.25 + Double(index) * 0.05)
        }
        self.path.strokeColor = GroupRulesColors.seal.cgColor
        self.slideOut(accepted: true, velocity: 0.0, delay: 0.95)
    }

    private func finish(accepted: Bool, velocity: CGFloat) {
        guard !self.isFinishing else {
            return
        }
        self.isFinishing = true
        self.slideOut(accepted: accepted, velocity: velocity, delay: 0.0)
    }

    private func slideOut(accepted: Bool, velocity: CGFloat, delay: Double) {
        let distance = self.sheetHeight + 80.0
        let duration = velocity > 800.0 ? 0.28 : 0.4
        UIView.animate(withDuration: duration, delay: delay, options: [.curveEaseIn], animations: {
            self.sheet.transform = CGAffineTransform(translationX: 0.0, y: distance)
            self.dimView.alpha = 0.0
        }, completion: { [weak self] _ in
            self?.finished?(accepted)
        })
    }

    // MARK: - Swiping down

    override func accessibilityPerformEscape() -> Bool {
        self.finish(accepted: false, velocity: 0.0)
        return true
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self).y
        if recognizer.state == .began {
            // The sheet moves only when its list is at its top (otherwise the list scrolls).
            self.panMovesSheet = self.scrollView.contentOffset.y <= 0.5
        }
        guard self.panMovesSheet else {
            return
        }
        switch recognizer.state {
        case .changed:
            // Down freely (the list held at its top), up only a little (with resistance) when the list does not scroll.
            if translation > 0.0 && self.scrollView.isScrollEnabled {
                self.scrollView.contentOffset = CGPoint()
            }
            let offset = translation > 0.0 ? translation : (self.scrollView.isScrollEnabled ? 0.0 : -sqrt(-translation) * 2.0)
            self.sheet.transform = CGAffineTransform(translationX: 0.0, y: offset)
            self.dimView.alpha = max(0.0, 1.0 - max(0.0, offset) / max(1.0, self.sheetHeight))
        case .ended, .cancelled:
            let velocity = recognizer.velocity(in: self).y
            if translation > self.sheetHeight * 0.3 || velocity > 700.0 {
                self.finish(accepted: false, velocity: velocity)
            } else {
                UIView.animate(withDuration: 0.5, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.0, options: [.allowUserInteraction], animations: {
                    self.sheet.transform = .identity
                    self.dimView.alpha = 1.0
                })
            }
        default:
            break
        }
    }
}
