import Foundation
import StoreKit
import SwiftUI

@MainActor
final class StoreModel: ObservableObject {
    @Published var pro: Product?
    @Published var trial: Product?
    @Published var busy = false
    @Published var notice: String?
    private var observer: Task<Void, Never>?
    private var refreshing = false

    func start(_ update: @escaping (Bool?, Date?) async throws -> Void) {
        guard !Launch.testing, observer == nil else { return }
        observer = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard case .verified(let transaction) = result,
                      transaction.productType == .nonConsumable,
                      [Launch.proID, Launch.trialID].contains(transaction.productID) else { continue }
                let saved = await Self.entitlements()
                do {
                    try await update(transaction.productID == Launch.proID && transaction.revocationDate != nil ? false : saved.0, saved.1)
                    await transaction.finish()
                } catch { self?.notice = (error as? WarrantyError ?? .store).message }
            }
            self?.observer = nil
        }
        Task { await syncEntitlements(update) }
    }

    func load() async {
        guard !Launch.testing, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let products = try await Product.products(for: [Launch.proID, Launch.trialID])
            pro = products.first { $0.id == Launch.proID && $0.type == .nonConsumable }
            trial = products.first { $0.id == Launch.trialID && $0.type == .nonConsumable && $0.price == 0 }
        } catch { self.notice = WarrantyError.store.message }
    }

    func buy(_ product: Product, update: (Bool?, Date?) async throws -> Void) async {
        guard !busy else { return }
        busy = true
        notice = nil
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result, transaction.revocationDate == nil,
                      transaction.productType == .nonConsumable, transaction.productID == product.id else { throw WarrantyError.store }
                try await update(transaction.productID == Launch.proID ? true : nil,
                                 transaction.productID == Launch.trialID ? transaction.originalPurchaseDate : nil)
                await transaction.finish()
                notice = L.t("pay.received")
            case .pending: notice = L.t("pay.pending")
            case .userCancelled: break
            @unknown default: throw WarrantyError.store
            }
        } catch { self.notice = (error as? WarrantyError ?? .store).message }
    }

    func restore(_ update: (Bool?, Date?) async throws -> Void) async {
        guard !busy, !Launch.testing else { return }
        busy = true
        notice = nil
        defer { busy = false }
        do {
            try await AppStore.sync()
            let value = await Self.entitlements()
            try await update(value.0 ?? false, value.1)
            notice = L.t(value.0 == true || value.1 != nil ? "pay.restored" : "pay.noPurchases")
        } catch { self.notice = (error as? WarrantyError ?? .store).message }
    }

    func syncEntitlements(_ update: (Bool?, Date?) async throws -> Void) async {
        guard !Launch.testing else { return }
        let value = await Self.entitlements()
        do { try await update(value.0, value.1) }
        catch { self.notice = (error as? WarrantyError ?? .store).message }
    }

    private static func entitlements() async -> (Bool?, Date?) {
        var pro: Bool?
        var trial: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil,
                  transaction.productType == .nonConsumable else { continue }
            if transaction.productID == Launch.proID { pro = true }
            if transaction.productID == Launch.trialID { trial = transaction.originalPurchaseDate }
        }
        if pro == nil, let latest = await StoreKit.Transaction.latest(for: Launch.proID),
           case .verified(let transaction) = latest, transaction.revocationDate != nil { pro = false }
        return (pro, trial)
    }
}
