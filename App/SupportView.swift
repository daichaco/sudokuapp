import StoreKit
import SwiftUI

/// 「開発を応援する」(投げ銭)の画面。
struct SupportView: View {
    let tips: TipStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("数独ヘルパーは無料で、広告もありません。気に入ったら、開発を応援してもらえるとうれしいです。応援しても、アプリの機能は変わりません。")
                        .font(.callout)
                }
                Section {
                    options
                } footer: {
                    Text("Apple の決済で、1回かぎりの支払いです。購読ではないので、くり返し請求されることはありません。")
                }
                if let outcome = tips.outcome {
                    Section { Text(message(for: outcome)).font(.callout) }
                }
            }
            .navigationTitle("開発を応援する")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } }
            }
            .task { await tips.load() }
        }
    }

    @ViewBuilder
    private var options: some View {
        switch tips.loadState {
        case .idle, .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("読み込み中…").foregroundStyle(.secondary)
            }
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Text("金額を読み込めませんでした。通信を確認して、もう一度お試しください。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("もう一度読み込む") { Task { await tips.reload() } }
            }
        case .loaded:
            ForEach(tips.products) { product in
                Button { Task { await tips.purchase(product) } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayName).foregroundStyle(.primary)
                            if !product.description.isEmpty {
                                Text(product.description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if tips.purchasing == product.id {
                            ProgressView()
                        } else {
                            Text(product.displayPrice).font(.headline.monospacedDigit())
                        }
                    }
                }
                .disabled(tips.purchasing != nil)
            }
        }
    }

    private func message(for outcome: TipStore.Outcome) -> String {
        switch outcome {
        case .thanks: "ありがとうございます! とても励みになります。"
        case .pending: "購入の承認を待っています。承認されると、完了します。"
        case .failed: "購入できませんでした。お金は引き落とされていません。もう一度お試しください。"
        }
    }
}
