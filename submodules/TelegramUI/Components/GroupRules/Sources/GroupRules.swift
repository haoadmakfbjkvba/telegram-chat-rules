import Foundation
import SwiftSignalKit
import TelegramCore

/// A group's rules, set by its admins. They are kept at the end of the group's description, so that no server change is
/// needed and any Telegram app shows them (as part of the description):
///
///     Weekend hikes around the city 🥾
///
///     📜 Rules ✅
///     1. Be kind to each other
///     2. No ads or self-promotion
///
/// The ✅ after "Rules" asks new members to accept them before they can write. This app hides the block from the
/// description and shows the rules on their own.
public struct GroupRules: Equatable {
    public static let symbol = "📜"
    public static let acceptanceMark = "✅"
    public static let maxRules = 10
    public static let maxRuleLength = 80
    /// How long a group's description can be, as `length(of:)` counts it.
    public static let maxDescriptionLength = 255

    public var rules: [String]
    /// Whether new members have to accept the rules before they can write.
    public var requiresAcceptance: Bool

    public init(rules: [String], requiresAcceptance: Bool) {
        self.rules = rules
        self.requiresAcceptance = requiresAcceptance
    }

    /// A short fingerprint of the rules (an accepted set is asked for again when they change).
    public var fingerprint: String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in self.rules.joined(separator: "\n").utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(hash, radix: 36)
    }

    // MARK: - The block in the description

    /// How the rules are written into the description (`header` is the localized word for "Rules").
    public func block(header: String) -> String {
        var lines = ["\(GroupRules.symbol) \(header)" + (self.requiresAcceptance ? " \(GroupRules.acceptanceMark)" : "")]
        for (index, rule) in self.rules.enumerated() {
            lines.append("\(index + 1). \(rule)")
        }
        return lines.joined(separator: "\n")
    }

    /// The description without its rules block, and the rules the block describes.
    public static func split(about: String?) -> (text: String, rules: GroupRules?) {
        guard let about, let parsed = GroupRules.parse(about: about) else {
            return (about ?? "", nil)
        }
        return (parsed.text, parsed.rules)
    }

    /// The word the block of this description is headed with ("Rules", in the language it was written in), if it has one.
    public static func header(about: String?) -> String? {
        guard let about else {
            return nil
        }
        return GroupRules.parse(about: about)?.header
    }

    /// The block is the last line beginning with the symbol that has numbered rules right after it ("1. Rule", "1) Rule"
    /// or without the space; blank lines between them are fine). Anything after the rules (added by another app, say) is
    /// part of the description.
    private static func parse(about: String) -> (text: String, rules: GroupRules, header: String?)? {
        let lines = about.components(separatedBy: "\n")
        for headerIndex in lines.indices.reversed() {
            let headerLine = lines[headerIndex].trimmingCharacters(in: .whitespaces)
            guard headerLine.hasPrefix(GroupRules.symbol) else {
                continue
            }
            var rules: [String] = []
            var endIndex = headerIndex + 1
            var index = headerIndex + 1
            while index < lines.count {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    index += 1
                    continue
                }
                guard let range = trimmed.range(of: "^[0-9]{1,2}[.)]\\s*", options: .regularExpression) else {
                    break
                }
                let rule = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !rule.isEmpty {
                    rules.append(rule)
                }
                index += 1
                endIndex = index
            }
            guard !rules.isEmpty else {
                continue
            }
            let before = lines[..<headerIndex].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let after = lines[endIndex...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let text = [before, after].filter { !$0.isEmpty }.joined(separator: "\n\n")
            var header = String(headerLine.dropFirst(GroupRules.symbol.count))
            header = header.replacingOccurrences(of: GroupRules.acceptanceMark, with: "").trimmingCharacters(in: .whitespaces)
            return (text, GroupRules(rules: rules, requiresAcceptance: headerLine.contains(GroupRules.acceptanceMark)), header.isEmpty ? nil : header)
        }
        return nil
    }

    /// The description `text` (without a block of its own) with the block of `rules` after it (or without one).
    public static func about(text: String, rules: GroupRules?, header: String) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rules, !rules.rules.isEmpty else {
            return text
        }
        let block = rules.block(header: header)
        return text.isEmpty ? block : text + "\n\n" + block
    }

    /// The length of a description as the server counts it (UTF-16 units, the larger count).
    public static func length(of about: String) -> Int {
        return about.utf16.count
    }
}

/// Which groups' rules the account has accepted, and where the prompt to accept is showing. Kept on the device, per
/// account. Safe from any thread; changes are told through `updated`.
public final class GroupRulesStore {
    public static let shared = GroupRulesStore()

    private let lock = NSLock()
    private var promptingKeys = Set<String>()
    private let updatedPipe = ValuePipe<EnginePeer.Id>()

    /// The group whose acceptance or prompt changed.
    public var updated: Signal<EnginePeer.Id, NoError> {
        return self.updatedPipe.signal()
    }

    private static func key(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id) -> String {
        return "GroupRules.Accepted.\(accountPeerId.toInt64()).\(peerId.toInt64())"
    }

    private static func promptingKey(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id) -> String {
        return "\(accountPeerId.toInt64()).\(peerId.toInt64())"
    }

    /// Whether the account has accepted these very rules of the group.
    public func hasAccepted(_ rules: GroupRules, peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) -> Bool {
        return UserDefaults.standard.string(forKey: GroupRulesStore.key(accountPeerId: accountPeerId, peerId: peerId)) == rules.fingerprint
    }

    public func accept(_ rules: GroupRules, peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) {
        UserDefaults.standard.set(rules.fingerprint, forKey: GroupRulesStore.key(accountPeerId: accountPeerId, peerId: peerId))
        self.lock.lock()
        self.promptingKeys.remove(GroupRulesStore.promptingKey(accountPeerId: accountPeerId, peerId: peerId))
        self.lock.unlock()
        self.updatedPipe.putNext(peerId)
    }

    /// Whether the bar asking to accept the rules replaces the Join button of the group (after the rules were closed
    /// without accepting them). Only while the app runs.
    public func isPrompting(_ peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) -> Bool {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.promptingKeys.contains(GroupRulesStore.promptingKey(accountPeerId: accountPeerId, peerId: peerId))
    }

    public func setPrompting(_ peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id, _ value: Bool) {
        let key = GroupRulesStore.promptingKey(accountPeerId: accountPeerId, peerId: peerId)
        self.lock.lock()
        let changed: Bool
        if value {
            changed = self.promptingKeys.insert(key).inserted
        } else {
            changed = self.promptingKeys.remove(key) != nil
        }
        self.lock.unlock()
        if changed {
            self.updatedPipe.putNext(peerId)
        }
    }
}

/// A chat that shows a group's rules before Join goes through.
public protocol GroupRulesGate: AnyObject {
    /// Called by Join: true if the rules are shown first (and `join` is called once they are accepted).
    func groupRulesBeforeJoin(join: @escaping () -> Void) -> Bool
}
