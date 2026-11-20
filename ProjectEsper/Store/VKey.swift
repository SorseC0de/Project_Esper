import EsperSim
import StoreKit
import SwiftUI

/// The V-Key, the one in-app purchase: the whole game. Without it the game is free to try: Rounds on the
/// Wreck Center, Topaz or Larimar (the outfits free in either), the Tutorial, and online the same.
/// Every build has it until the App Store release (`givenBeforeRelease`); a debug build's V-KEY switch
/// on the title takes it away to see the locks. The store's side is `VKeyStore`.
enum VKey {
    /// The product in App Store Connect: non-consumable.
    static let productID = "com.sorsec0de.projectesper.vkey"

    static let freeModes: Set<GameMode> = [.rounds]
    static let freeStages: Set<StageChoice> = [.wreckCenter]
    static let freeColours: [EnergyColour] = [.orange, .teal]

    /// Whether this device has it, read anywhere: the store's word, kept between launches so it's
    /// right before the store answers.
    nonisolated(unsafe) fileprivate(set) static var owned = ownedNow(bought: UserDefaults.standard.bool(forKey: boughtKey))

    fileprivate static let boughtKey = "esper.vkey.bought"
    /// Debug: the V-KEY switch on the title, taking the key away.
    static let debugLockedKey = "esper.vkey.debugLocked"
    /// Everyone has the key until the game is public on the App Store, so testers and recordings never
    /// meet the paywall. Set false in the release that goes public.
    static let givenBeforeRelease = true

    fileprivate static func ownedNow(bought: Bool) -> Bool {
        #if DEBUG
        bought || !UserDefaults.standard.bool(forKey: debugLockedKey)
        #else
        bought || givenBeforeRelease
        #endif
    }

    static func opens(_ mode: GameMode) -> Bool { owned || freeModes.contains(mode) }
    static func opens(_ stage: StageChoice) -> Bool { owned || freeStages.contains(stage) }
    static func opens(_ colour: EnergyColour) -> Bool { owned || freeColours.contains(colour) }
}

/// The V-Key's purchase: owned as the store says, bought, restored.
@MainActor
final class VKeyStore: ObservableObject {
    static let shared = VKeyStore()
    @Published private(set) var shownOwned = VKey.owned
    @Published private(set) var product: Product?
    @Published private(set) var busy = false
    /// A word under the buttons: pending, failed, nothing to restore.
    @Published var note: String?
    private var updates: Task<Void, Never>?

    private init() {}

    /// At launch: purchases made elsewhere or approved later heard as they come, what's owned
    /// asked for, and the product loaded for its price.
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refresh()
                }
            }
        }
        Task {
            await refresh()
            product = try? await Product.products(for: [VKey.productID]).first
        }
    }

    /// Owned as the store has it now: a verified, unrevoked entitlement.
    func refresh() async {
        var bought = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == VKey.productID, transaction.revocationDate == nil {
                bought = true
            }
        }
        set(bought: bought)
    }

    private func set(bought: Bool) {
        UserDefaults.standard.set(bought, forKey: VKey.boughtKey)
        VKey.owned = VKey.ownedNow(bought: bought)
        shownOwned = VKey.owned
    }

    /// Debug: the key taken away or given back, as the title's V-KEY switch says.
    func debugToggleLocked() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: VKey.debugLockedKey), forKey: VKey.debugLockedKey)
        set(bought: defaults.bool(forKey: VKey.boughtKey))
    }

    func buy() {
        guard !busy else { return }
        busy = true
        note = nil
        Task {
            defer { busy = false }
            do {
                if product == nil { product = try await Product.products(for: [VKey.productID]).first }
                guard let product = self.product else {
                    note = "THE STORE CAN'T BE REACHED"
                    return
                }
                switch try await product.purchase() {
                case .success(.verified(let transaction)):
                    await transaction.finish()
                    await refresh()
                case .success(.unverified):
                    note = "THE PURCHASE COULDN'T BE VERIFIED"
                case .pending:
                    note = "WAITING FOR APPROVAL"
                case .userCancelled:
                    break
                @unknown default:
                    break
                }
            } catch {
                note = "THE PURCHASE DIDN'T GO THROUGH"
            }
        }
    }

    /// The store asked again for what this Apple Account owns.
    func restore() {
        guard !busy else { return }
        busy = true
        note = nil
        Task {
            defer { busy = false }
            try? await AppStore.sync()
            await refresh()
            if !VKey.owned { note = "NO V-KEY ON THIS ACCOUNT" }
        }
    }
}

extension EnergyColour {
    /// Free to try's colour in place of this one: itself if it's free, else Topaz on the first side, Larimar on the second.
    func playable(for player: Int) -> EnergyColour {
        VKey.opens(self) ? self : (player == 0 ? .orange : .teal)
    }

    /// The colour a side gives way to when it matches the other's: the opposite with the key, the
    /// other free colour without.
    func givingWay(unlocked: Bool) -> EnergyColour {
        guard !unlocked else { return opposite }
        return self == .teal ? .orange : .teal
    }
}
