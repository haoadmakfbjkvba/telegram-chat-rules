import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import PresentationDataUtils
import UndoUI
import OldChannelsController
import GroupRules

/// What the bar in place of the message field (or of Join) asks for.
enum GroupRulesPrompt {
    /// Accept the rules to join (they were closed without accepting them).
    case join
    /// Accept the rules to write (the account is in the group).
    case write
    /// Accepted: joining.
    case joining
}

/// What a group chat knows of the group's rules: the rules from its description, and whether the account has to accept
/// them before it can join or write.
final class ChatControllerGroupRulesState {
    var rules: GroupRules?
    var storeDisposable: Disposable?
    var joinDisposable: Disposable?
    /// Joining after the rules were accepted from the bar: the bar stays (saying so) until the account is in.
    var isJoining = false
    weak var sheet: GroupRulesSheetController?

    deinit {
        self.storeDisposable?.dispose()
        self.joinDisposable?.dispose()
    }
}

extension ChatControllerImpl: GroupRulesGate {
    /// The group this chat is (a group or a supergroup, not a channel's posts, a forum or direct messages), with whether
    /// the account is in it, whether it can write there and whether it manages it.
    private var groupRulesPeer: (peer: EnginePeer, isMember: Bool, canWrite: Bool, isAdmin: Bool)? {
        guard case .peer = self.chatLocation, self.chatLocation.threadId == nil else {
            return nil
        }
        switch self.subject {
        case .none, .message:
            break
        default:
            return nil
        }
        let peer = self.contentData?.state.renderedPeer?.peer ?? self.presentationInterfaceState.renderedPeer?.peer
        if let channel = peer as? TelegramChannel {
            guard case .group = channel.info, !channel.isForumOrMonoForum else {
                return nil
            }
            let isMember: Bool
            if case .member = channel.participationStatus {
                isMember = true
            } else {
                isMember = false
            }
            let canWrite = channel.hasPermission(.sendSomething) && !channel.flags.contains(.isGigagroup)
            return (EnginePeer(channel), isMember, canWrite, channel.flags.contains(.isCreator) || channel.adminRights != nil)
        } else if let group = peer as? TelegramGroup {
            let isAdmin: Bool
            switch group.role {
            case .creator, .admin:
                isAdmin = true
            case .member:
                isAdmin = false
            }
            return (EnginePeer(group), group.membership == .Member, group.hasPermission(.sendSomething), isAdmin)
        }
        return nil
    }

    /// The rules the account still has to accept here (admins never do).
    private var pendingGroupRules: GroupRules? {
        guard let rules = self.groupRulesState.rules, rules.requiresAcceptance, let info = self.groupRulesPeer, !info.isAdmin else {
            return nil
        }
        if GroupRulesStore.shared.hasAccepted(rules, peerId: info.peer.id, accountPeerId: self.context.account.peerId) {
            return nil
        }
        return rules
    }

    /// The bar shown in place of the message field (or of Join) about the rules, if any.
    var groupRulesPrompt: GroupRulesPrompt? {
        guard let info = self.groupRulesPeer else {
            return nil
        }
        if self.groupRulesState.isJoining && !info.isMember {
            return .joining
        }
        guard self.pendingGroupRules != nil else {
            return nil
        }
        if info.isMember {
            // Only in place of a message field (not of the notices of a member who cannot write).
            return info.canWrite ? .write : nil
        }
        return GroupRulesStore.shared.isPrompting(info.peer.id, accountPeerId: self.context.account.peerId) ? .join : nil
    }

    /// The group's description (its rules) has been read or changed.
    func updateGroupRulesFromContentData() {
        let state = self.groupRulesState
        if state.storeDisposable == nil {
            state.storeDisposable = (GroupRulesStore.shared.updated
            |> deliverOnMainQueue).startStrict(next: { [weak self] peerId in
                guard let self, peerId == self.chatLocation.peerId else {
                    return
                }
                self.updateGroupRulesPanel()
            })
        }
        var about: String?
        if let cachedData = self.contentData?.state.peerView?.cachedData as? CachedChannelData {
            about = cachedData.about
        } else if let cachedData = self.contentData?.state.peerView?.cachedData as? CachedGroupData {
            about = cachedData.about
        }
        if state.isJoining, self.groupRulesPeer?.isMember == true {
            // In: the message field takes the bar's place.
            state.isJoining = false
            Queue.mainQueue().justDispatch { [weak self] in
                self?.updateGroupRulesPanel()
            }
        }
        let rules = self.groupRulesPeer == nil ? nil : GroupRules.split(about: about).rules
        guard rules != state.rules else {
            return
        }
        state.rules = rules
        // Not in the middle of the chat's own update.
        Queue.mainQueue().justDispatch { [weak self] in
            self?.updateGroupRulesPanel()
        }
    }

    /// Chooses the input panel again (the bar comes or goes): the chat's state itself has not changed.
    private func updateGroupRulesPanel() {
        self.updateChatPresentationInterfaceState(animated: true, interactive: false, { $0 })
        self.requestLayout(transition: .animated(duration: 0.4, curve: .spring))
    }

    // MARK: - GroupRulesGate

    public func groupRulesBeforeJoin(join: @escaping () -> Void) -> Bool {
        guard self.pendingGroupRules != nil else {
            return false
        }
        self.presentGroupRules(fromPrompt: false, join: join)
        return true
    }

    // MARK: - The rules

    /// Shows the rules. Accepted: they are kept as accepted and the account joins (by `join`, or by itself from the
    /// bar). Closed: the bar asking to accept them takes the place of Join.
    func presentGroupRules(fromPrompt: Bool, join: (() -> Void)? = nil) {
        guard self.groupRulesState.sheet == nil, let rules = self.pendingGroupRules, let info = self.groupRulesPeer else {
            return
        }
        let context = self.context
        let peerId = info.peer.id
        let accountPeerId = context.account.peerId
        let strings = self.presentationData.strings
        let state = self.groupRulesState
        self.chatDisplayNode.dismissInput()
        let sheet = GroupRulesSheetController(presentationData: self.presentationData, text: info.isMember ? strings.GroupRules_SheetTextMember(info.peer.compactDisplayTitle).string : strings.GroupRules_SheetText(info.peer.compactDisplayTitle).string, rules: rules, acceptTitle: info.isMember ? strings.GroupRules_AcceptMember : strings.GroupRules_AcceptJoin, isSeenBefore: fromPrompt, completion: { [weak self] accepted in
            if accepted {
                if !info.isMember && join == nil {
                    // Joining from the bar: it turns into "Joining…" as the rules are taken as accepted (not into Join
                    // for a moment).
                    state.isJoining = true
                }
                GroupRulesStore.shared.accept(rules, peerId: peerId, accountPeerId: accountPeerId)
                if !info.isMember {
                    if let join {
                        join()
                    } else {
                        self?.joinGroupAfterRules(peerId: peerId)
                    }
                }
            } else if !info.isMember {
                GroupRulesStore.shared.setPrompting(peerId, accountPeerId: accountPeerId, true)
            }
        })
        self.groupRulesState.sheet = sheet
        self.present(sheet, in: .window(.root))
    }

    /// Joins the group once its rules are accepted from the bar (where Join was). The bar says so meanwhile.
    private func joinGroupAfterRules(peerId: EnginePeer.Id) {
        let context = self.context
        let presentationData = self.presentationData
        let state = self.groupRulesState
        let stopJoining: () -> Void = { [weak self] in
            guard let self, state.isJoining else {
                return
            }
            state.isJoining = false
            self.updateGroupRulesPanel()
        }
        state.isJoining = true
        self.updateGroupRulesPanel()
        state.joinDisposable?.dispose()
        state.joinDisposable = (context.peerChannelMemberCategoriesContextsManager.join(engine: context.engine, peerId: peerId, hash: nil)
        |> deliverOnMainQueue).startStrict(next: { [weak self] result in
            if case let .webView(webView) = result, let self {
                stopJoining()
                context.sharedContext.openJoinChatWebView(context: context, parentController: self, updatedPresentationData: self.updatedPresentationData, webView: webView, chatTitle: self.groupRulesPeer?.peer.compactDisplayTitle ?? "")
            }
        }, error: { [weak self] error in
            stopJoining()
            guard let self else {
                return
            }
            // As Join does it.
            switch error {
            case .inviteRequestSent:
                self.present(UndoOverlayController(presentationData: presentationData, content: .inviteRequestSent(title: presentationData.strings.Group_RequestToJoinSent, text: presentationData.strings.Group_RequestToJoinSentDescriptionGroup), elevatedLayout: true, animateInAsReplacement: false, action: { _ in return false }), in: .current)
            case .tooMuchJoined:
                self.push(oldChannelsController(context: context, intent: .join, completed: { [weak self] value in
                    if value {
                        self?.joinGroupAfterRules(peerId: peerId)
                    }
                }))
            case .tooMuchUsers:
                self.present(textAlertController(context: context, title: nil, text: presentationData.strings.Conversation_UsersTooMuchError, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
            case .generic:
                self.present(textAlertController(context: context, title: nil, text: presentationData.strings.Group_ErrorAccessDenied, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
            }
        }, completed: {
            // The account is in (the chat shows it as it learns it); if it has not learnt it by now, the bar goes anyway.
            Queue.mainQueue().after(4.0, {
                stopJoining()
            })
        })
    }
}
