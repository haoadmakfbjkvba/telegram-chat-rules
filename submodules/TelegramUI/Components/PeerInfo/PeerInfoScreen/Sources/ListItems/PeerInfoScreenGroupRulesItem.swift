import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import AccountContext
import GroupRules

/// Group Rules among a group's settings: the scroll (sealed when new members have to accept the rules), the title, how
/// many rules there are (or Off) and an arrow. The first times it is seen the scroll unrolls and the title writes itself;
/// when the rules change, the count rises into place and the scroll is sealed or unsealed.
final class PeerInfoScreenGroupRulesItem: PeerInfoScreenItem {
    private static let introductionsKey = "GroupRulesSettingsItem.Introductions"
    private static let introductionCount = 3

    let id: AnyHashable
    let title: String
    let value: String
    let isSealed: Bool
    let action: (() -> Void)?

    init(id: AnyHashable, title: String, value: String, isSealed: Bool, action: (() -> Void)?) {
        self.id = id
        self.title = title
        self.value = value
        self.isSealed = isSealed
        self.action = action
    }

    func node() -> PeerInfoScreenItemNode {
        let introduces = UserDefaults.standard.integer(forKey: PeerInfoScreenGroupRulesItem.introductionsKey) < PeerInfoScreenGroupRulesItem.introductionCount
        return PeerInfoScreenGroupRulesItemNode(introduces: introduces)
    }

    fileprivate static func noteIntroduction() {
        let count = UserDefaults.standard.integer(forKey: PeerInfoScreenGroupRulesItem.introductionsKey)
        UserDefaults.standard.set(count + 1, forKey: PeerInfoScreenGroupRulesItem.introductionsKey)
    }
}

private final class PeerInfoScreenGroupRulesItemNode: PeerInfoScreenItemNode {
    private let selectionNode: PeerInfoScreenSelectableBackgroundNode
    private let maskNode: ASImageNode
    private let iconView = GroupRulesIconView()
    private let titleView = RulesTextView()
    private let valueView = RulesTextView()
    private let arrowNode: ASImageNode
    private let bottomSeparatorNode: ASDisplayNode
    private let activateArea: AccessibilityAreaNode

    private var item: PeerInfoScreenGroupRulesItem?
    private let introduces: Bool
    private var didIntroduce = false

    init(introduces: Bool) {
        self.introduces = introduces
        var bringToFrontForHighlightImpl: (() -> Void)?
        self.selectionNode = PeerInfoScreenSelectableBackgroundNode(bringToFrontForHighlight: { bringToFrontForHighlightImpl?() })
        self.maskNode = ASImageNode()
        self.maskNode.isUserInteractionEnabled = false
        self.arrowNode = ASImageNode()
        self.arrowNode.displaysAsynchronously = false
        self.arrowNode.isUserInteractionEnabled = false
        self.arrowNode.displayWithoutProcessing = true
        self.bottomSeparatorNode = ASDisplayNode()
        self.bottomSeparatorNode.isLayerBacked = true
        self.activateArea = AccessibilityAreaNode()

        super.init()

        bringToFrontForHighlightImpl = { [weak self] in
            self?.bringToFrontForHighlight?()
        }

        self.addSubnode(self.bottomSeparatorNode)
        self.addSubnode(self.selectionNode)
        self.addSubnode(self.maskNode)
        self.addSubnode(self.arrowNode)
        self.addSubnode(self.activateArea)
    }

    override func didLoad() {
        super.didLoad()
        for view in [self.iconView, self.titleView, self.valueView] as [UIView] {
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            self.view.insertSubview(view, belowSubview: self.arrowNode.view)
        }
        if self.introduces && !UIAccessibility.isReduceMotionEnabled {
            // The row comes in by itself once the list has opened: until then its scroll and text are not there.
            self.iconView.alpha = 0.0
            self.titleView.alpha = 0.0
            self.valueView.alpha = 0.0
        }
    }

    override func didEnterHierarchy() {
        super.didEnterHierarchy()
        if self.introduces && !self.didIntroduce {
            self.didIntroduce = true
            PeerInfoScreenGroupRulesItem.noteIntroduction()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: { [weak self] in
                self?.playIntroduction()
            })
        }
    }

    override func update(context: AccountContext, width: CGFloat, safeInsets: UIEdgeInsets, presentationData: PresentationData, item: PeerInfoScreenItem, topItem: PeerInfoScreenItem?, bottomItem: PeerInfoScreenItem?, hasCorners: Bool, transition: ContainedViewLayoutTransition) -> CGFloat {
        guard let item = item as? PeerInfoScreenGroupRulesItem else {
            return 10.0
        }
        let previousItem = self.item
        self.item = item
        self.selectionNode.pressed = item.action

        let theme = presentationData.theme
        let sideInset: CGFloat = 16.0 + safeInsets.left
        let sideInsetRight: CGFloat = 16.0 + safeInsets.right
        let leftInset = sideInset + 29.0 + 16.0
        let rightInset = sideInsetRight + 18.0
        let titleFont = Font.regular(presentationData.listsFontSize.itemListBaseFontSize)

        self.bottomSeparatorNode.backgroundColor = theme.list.itemBlocksSeparatorColor

        let valueSize = self.valueView.update(text: NSAttributedString(string: item.value, attributes: [.font: titleFont, .foregroundColor: theme.list.itemSecondaryTextColor]), width: max(1.0, width * 0.4), maxLines: 1)
        let titleWidth = max(1.0, width - leftInset - rightInset - valueSize.width - 12.0)
        let titleSize = self.titleView.update(text: NSAttributedString(string: item.title, attributes: [.font: titleFont, .foregroundColor: theme.list.itemPrimaryTextColor]), width: titleWidth, maxLines: 1)

        let height = titleSize.height + 32.0
        let iconSize: CGFloat = 30.0
        self.iconView.frame = CGRect(x: sideInset, y: floorToScreenPixels((height - iconSize) * 0.5), width: iconSize, height: iconSize)
        self.titleView.frame = CGRect(origin: CGPoint(x: leftInset, y: floorToScreenPixels((height - titleSize.height) * 0.5)), size: titleSize)
        self.valueView.frame = CGRect(origin: CGPoint(x: width - rightInset - valueSize.width, y: floorToScreenPixels((height - valueSize.height) * 0.5)), size: valueSize)

        if let previousItem {
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            // The rules change as their editor saves them and goes back here: the change plays once this list is in
            // view again.
            let shownDelay = 0.5
            if previousItem.value != item.value && !reduceMotion {
                // New rules: the scroll unrolls again and the count rises into place.
                self.iconView.animateUnroll(delay: shownDelay)
                let _ = self.valueView.animateLettersIn(delay: shownDelay + 0.2, stagger: 0.03, offset: 10.0)
            }
            if previousItem.isSealed != item.isSealed {
                if item.isSealed && !reduceMotion {
                    // After the tile's pop of the unrolling (both scale the tile).
                    self.iconView.stampSeal(delay: shownDelay + (previousItem.value != item.value ? 0.8 : 0.1))
                } else if !item.isSealed && !reduceMotion {
                    self.iconView.liftSeal()
                } else {
                    self.iconView.isSealed = item.isSealed
                }
            }
        } else {
            self.iconView.isSealed = item.isSealed
        }

        if let arrowImage = PresentationResourcesItemList.disclosureArrowImage(theme) {
            self.arrowNode.image = arrowImage
            let arrowFrame = CGRect(origin: CGPoint(x: width - 7.0 - arrowImage.size.width - safeInsets.right, y: floorToScreenPixels((height - arrowImage.size.height) / 2.0)), size: arrowImage.size)
            transition.updateFrame(node: self.arrowNode, frame: arrowFrame)
        }

        self.activateArea.accessibilityLabel = item.title
        self.activateArea.accessibilityValue = item.value
        self.activateArea.accessibilityTraits = [.button]

        let hasCorners = hasCorners && (topItem == nil || bottomItem == nil)
        let hasTopCorners = hasCorners && topItem == nil
        let hasBottomCorners = hasCorners && bottomItem == nil
        self.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(theme, top: hasTopCorners, bottom: hasBottomCorners, glass: true) : nil
        self.maskNode.frame = CGRect(origin: CGPoint(x: safeInsets.left, y: 0.0), size: CGSize(width: width - safeInsets.left - safeInsets.right, height: height))
        self.bottomSeparatorNode.isHidden = hasBottomCorners

        let highlightNodeOffset: CGFloat = topItem == nil ? 0.0 : UIScreenPixel
        self.selectionNode.update(size: CGSize(width: width, height: height + highlightNodeOffset), theme: theme, transition: transition)
        transition.updateFrame(node: self.selectionNode, frame: CGRect(origin: CGPoint(x: 0.0, y: -highlightNodeOffset), size: CGSize(width: width, height: height + highlightNodeOffset)))
        transition.updateFrame(node: self.bottomSeparatorNode, frame: CGRect(origin: CGPoint(x: leftInset - 1.0, y: height - UIScreenPixel), size: CGSize(width: width - leftInset + 1.0 - 16.0, height: UIScreenPixel)))
        transition.updateAlpha(node: self.bottomSeparatorNode, alpha: bottomItem == nil ? 0.0 : 1.0)
        self.activateArea.frame = CGRect(origin: CGPoint(x: safeInsets.left, y: 0.0), size: CGSize(width: width - safeInsets.left - safeInsets.right, height: height))
        return height
    }

    /// The scroll unrolls, the title writes itself letter by letter and the count rises in after it.
    private func playIntroduction() {
        guard self.isNodeLoaded else {
            return
        }
        self.iconView.alpha = 1.0
        self.titleView.alpha = 1.0
        self.valueView.alpha = 1.0
        guard !UIAccessibility.isReduceMotionEnabled else {
            return
        }
        self.iconView.animateUnroll(delay: 0.0)
        let titleEnd = self.titleView.animateLettersIn(delay: 0.12, stagger: 0.026)
        rulesAnimateRiseIn(self.valueView.layer, delay: min(titleEnd, 0.5), offset: 8.0, scale: 0.9, blur: 5.0)
    }
}
