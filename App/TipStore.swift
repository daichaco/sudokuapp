import Observation
import StoreKit

/// 投げ銭(アプリ内課金の消耗型)。支払っても、アプリの機能は何も変わらない。
@MainActor
@Observable
final class TipStore {
    /// App Store Connect に登録する商品ID(種類は「消耗型」)。
    static let productIDs = [
        "com.taiki.SudokuHelper.tip.160",
        "com.taiki.SudokuHelper.tip.480",
        "com.taiki.SudokuHelper.tip.1000",
    ]

    enum LoadState { case idle, loading, loaded, failed }
    enum Outcome { case thanks, pending, failed }

    private(set) var products: [Product] = []
    private(set) var loadState: LoadState = .idle
    /// 購入手続き中の商品ID。
    private(set) var purchasing: String?
    private(set) var outcome: Outcome?

    /// 商品の名前と価格を読み込む。読み込み済み・読み込み中なら何もしない。
    func load() async {
        guard loadState != .loading, loadState != .loaded else { return }
        loadState = .loading
        do {
            products = try await Product.products(for: Self.productIDs).sorted { $0.price < $1.price }
            loadState = products.isEmpty ? .failed : .loaded
        } catch {
            loadState = .failed
        }
    }

    func reload() async {
        loadState = .idle
        await load()
    }

    func purchase(_ product: Product) async {
        guard purchasing == nil else { return }
        purchasing = product.id
        outcome = nil
        defer { purchasing = nil }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                outcome = .thanks
            case .success(.unverified):
                outcome = .failed
            case .pending:
                outcome = .pending      // 「承認と購入のリクエスト」など。承認されたら updates に届く
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            outcome = .failed
        }
    }

    /// 終わっていない購入(アプリが落ちたとき、保留が承認されたとき)を完了させる。アプリの起動中ずっと待つ。
    func finishPendingTransactions() async {
        for await update in Transaction.updates {
            guard case .verified(let transaction) = update else { continue }
            await transaction.finish()
            outcome = .thanks
        }
    }
}
