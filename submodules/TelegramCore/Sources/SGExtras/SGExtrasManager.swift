import Foundation
import Postbox
import SwiftSignalKit

// Shadowgram: settings and state for the features Shadowgram adds on top of AyuGram
// (fake phone number, poll result peeking). Stored in `AYGSharedDefaults.store` like the
// AYG settings, under the `SG.` prefix.
public final class SGExtrasManager {
    public static let shared = SGExtrasManager()

    private enum Keys {
        static let fakePhoneEnabled = "SG.fakePhone.enabled"
        static let fakePhoneNumber = "SG.fakePhone.number"
        static let pollPeekEnabled = "SG.pollPeek.enabled"
    }

    public static let settingsChangedNotification = Notification.Name("SGExtrasSettingsChanged")

    private let defaults = AYGSharedDefaults.store
    private let lock = NSLock()
    private var peekedPollResults: [MediaId: SGPeekedPollResults] = [:]

    private init() {}

    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: SGExtrasManager.settingsChangedNotification, object: nil)
    }

    // MARK: - Fake phone number

    public var fakePhoneEnabled: Bool {
        get {
            return self.defaults.bool(forKey: Keys.fakePhoneEnabled)
        }
        set {
            self.defaults.set(newValue, forKey: Keys.fakePhoneEnabled)
            self.notifySettingsChanged()
        }
    }

    /// Digits only, the way `TelegramUser.phone` stores numbers, so the regular
    /// phone formatter can format it.
    public var fakePhoneNumber: String {
        get {
            return self.defaults.string(forKey: Keys.fakePhoneNumber) ?? ""
        }
        set {
            let digits = newValue.filter { $0.isASCII && $0.isNumber }
            self.defaults.set(digits, forKey: Keys.fakePhoneNumber)
            self.notifySettingsChanged()
        }
    }

    /// The number to show for the current account's own phone.
    public func displayedOwnPhone(_ realPhone: String?) -> String? {
        let fake = self.fakePhoneNumber
        if self.fakePhoneEnabled && !fake.isEmpty {
            return fake
        }
        return realPhone
    }

    // MARK: - Poll result peeking

    public var pollPeekEnabled: Bool {
        get {
            if self.defaults.object(forKey: Keys.pollPeekEnabled) == nil {
                return true
            }
            return self.defaults.bool(forKey: Keys.pollPeekEnabled)
        }
        set {
            self.defaults.set(newValue, forKey: Keys.pollPeekEnabled)
            self.notifySettingsChanged()
        }
    }

    /// Peeking votes and immediately retracts, so only polls where that leaves no trace
    /// qualify: anonymous (no voter list), re-votable, not a quiz (answers are final),
    /// results not hidden until close, still open and not voted in yet.
    public func canPeekResults(poll: TelegramMediaPoll) -> Bool {
        guard self.pollPeekEnabled else {
            return false
        }
        guard case .anonymous = poll.publicity, case .poll = poll.kind else {
            return false
        }
        if poll.isClosed || poll.revotingDisabled || poll.hideResultsUntilClose || poll.options.isEmpty {
            return false
        }
        if let voters = poll.results.voters, voters.contains(where: { $0.selected }) {
            return false
        }
        return self.peekedResults(pollId: poll.pollId) == nil
    }

    public func peekedResults(pollId: MediaId) -> SGPeekedPollResults? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.peekedPollResults[pollId]
    }

    fileprivate func storePeekedResults(_ results: SGPeekedPollResults, pollId: MediaId) {
        self.lock.lock()
        self.peekedPollResults[pollId] = results
        self.lock.unlock()
    }
}

public struct SGPeekedPollResults {
    public let voters: [TelegramMediaPollOptionVoters]
    public let totalVoters: Int32
}

public extension TelegramEngine.Messages {
    /// Votes for the first option, remembers the results the server returns, then
    /// retracts the vote. Our own vote is subtracted from the remembered counts.
    func sgPeekPollResults(messageId: MessageId, poll: TelegramMediaPoll) -> Signal<Bool, NoError> {
        guard let option = poll.options.first else {
            return .single(false)
        }
        let pollId = poll.pollId
        let votedIdentifier = option.opaqueIdentifier
        return self.requestMessageSelectPollOption(messageId: messageId, opaqueIdentifiers: [votedIdentifier])
        |> map(Optional.init)
        |> `catch` { _ -> Signal<TelegramMediaPoll??, NoError> in
            return .single(nil)
        }
        |> mapToSignal { updatedPoll -> Signal<Bool, NoError> in
            guard let updatedPoll = updatedPoll ?? nil, let voters = updatedPoll.results.voters, let totalVoters = updatedPoll.results.totalVoters else {
                return .single(false)
            }
            let adjustedVoters = voters.map { voter -> TelegramMediaPollOptionVoters in
                var count = voter.count
                if voter.opaqueIdentifier == votedIdentifier, let value = count {
                    count = max(0, value - 1)
                }
                return TelegramMediaPollOptionVoters(selected: false, opaqueIdentifier: voter.opaqueIdentifier, count: count, isCorrect: voter.isCorrect, recentVoters: voter.recentVoters)
            }
            SGExtrasManager.shared.storePeekedResults(SGPeekedPollResults(voters: adjustedVoters, totalVoters: max(0, totalVoters - 1)), pollId: pollId)
            return self.requestMessageSelectPollOption(messageId: messageId, opaqueIdentifiers: [])
            |> map { _ -> Bool in
                return true
            }
            |> `catch` { _ -> Signal<Bool, NoError> in
                return .single(true)
            }
        }
    }
}
