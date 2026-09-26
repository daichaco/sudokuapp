import Observation
import SudokuCore
import SwiftUI

/// 盤面の状態のスナップショット(「戻す」と自動保存に使う)。
struct GameSnapshot: Codable, Equatable {
    var cells: [Int]
    var given: [Int]
    var isSetup: Bool
}

@MainActor
@Observable
final class GameViewModel {
    var board = Board()
    /// 問題として固定された数字のマス(遊んでいる間は変更不可)。
    var given = Set<Int>()
    /// true: 問題を入力・修正する段階。false: 解いて遊ぶ段階。
    var isSetup = true
    var selected: Int?
    var showCandidates = false
    var showMistakes = false
    var hint: Hint?
    /// 1: 注目範囲だけ / 2: 場所と理由を表示。3回目のタップで入力する。
    var hintStage = 0
    var message: String?
    var isRecognizing = false

    /// 読み取りで判定に自信がなかったマス。確認・修正するまでオレンジで表示する。
    var uncertain = Set<Int>()

    /// 戻す用の履歴(古い順)。
    private var history: [GameSnapshot] = []
    private static let historyLimit = 200
    let gameID: UUID
    private let store: GameStore?

    /// `store` に nil を渡すと保存しない(テスト用)。
    init(record: GameRecord = GameRecord(), store: GameStore? = nil) {
        gameID = record.id
        self.store = store
        apply(record.snapshot)
        history = record.history
        selected = nil
    }

    var canUndo: Bool { !history.isEmpty }

    // MARK: 表示用

    var mistakes: Set<Int> {
        if isSetup { return Set(HintEngine.mistakes(in: board)) }          // 重複だけ常に赤表示
        return showMistakes ? Set(HintEngine.mistakes(in: board, given: given)) : []
    }

    /// ヒントで強調するマス(段階1: 根拠の範囲)。
    var hintRelated: Set<Int> {
        guard let hint, hintStage >= 1 else { return [] }
        return Set(hint.relatedIndices)
    }

    /// ヒントの答えのマス(段階2以降)。
    var hintTarget: Int? { hintStage >= 2 ? hint?.index : nil }

    var hintPanelText: String? {
        guard let hint else { return message }
        switch hintStage {
        case 1: return "黄色いマスに注目してください。もう一度「ヒント」を押すと場所を教えます。"
        default: return hint.explanation
        }
    }

    var hintButtonTitle: String {
        switch hintStage {
        case 0: "ヒント"
        case 1: "場所を見る"
        default: "入力する"
        }
    }

    // MARK: 操作

    func select(_ i: Int) {
        selected = i
        uncertain.remove(i)      // 開いて確認したマスは、もう印を付けない
    }

    func input(_ digit: Int) {
        guard let i = selected, canEdit(i), board.cells[i] != digit else { return }
        pushHistory()
        board.cells[i] = digit
        uncertain.remove(i)
        clearHint()
        message = nil
        save()
    }

    func erase() { input(0) }

    private func canEdit(_ i: Int) -> Bool { isSetup || !given.contains(i) }

    func startGame() {
        guard board.isConsistent else { message = "同じ行・列・ブロックに重複があります。赤いマスを直してください。"; return }
        guard board.cells.contains(where: { $0 != 0 }) else { message = "数字を入力するか、写真を読み取ってください。"; return }
        guard Solver.countSolutions(board) > 0 else { message = "この問題には解がありません。読み取りや入力を確認してください。"; return }
        pushHistory()
        given = Set((0..<81).filter { board.cells[$0] != 0 })
        isSetup = false
        uncertain = []
        selected = nil
        clearHint()
        message = nil
        save()
    }

    func editProblem() {
        pushHistory()
        isSetup = true
        clearHint()
        message = nil
        save()
    }

    /// 自分で入れた数字だけ消して最初から。
    func restart() {
        pushHistory()
        for i in 0..<81 where !given.contains(i) { board.cells[i] = 0 }
        clearHint()
        message = nil
        save()
    }

    func clearAll() {
        pushHistory()
        board = Board(); given = []; selected = nil; isSetup = true; uncertain = []
        clearHint(); message = nil
        save()
    }

    /// 直前の操作を取り消す。
    func undo() {
        guard let last = history.popLast() else { return }
        apply(last)
        uncertain = []
        clearHint()
        message = nil
        save()
    }

    func showSolution() {
        var problem = board
        if !isSetup { for i in 0..<81 where !given.contains(i) { problem.cells[i] = 0 } }
        guard let solution = Solver.solve(problem) else {
            message = "解けませんでした。入力に間違いがないか確認してください。"; return
        }
        pushHistory()
        board = solution
        clearHint()
        message = "解答を表示しました。"
        save()
    }

    func hintTapped() {
        if isSetup { message = "先に「開始」を押して問題を確定してください。"; return }
        if let hint, hintStage >= 2 {
            pushHistory()
            board.cells[hint.index] = hint.value
            selected = hint.index
            clearHint()
            if board.isComplete { message = "完成です! 🎉" }
            save()
            return
        }
        if hint != nil { hintStage += 1; return }

        if !HintEngine.mistakes(in: board, given: given).isEmpty {
            showMistakes = true
            message = "入力した数字に間違いがあります。赤いマスを直してからヒントを使えます。"
            return
        }
        guard let next = HintEngine.nextHint(for: board) else {
            message = board.isComplete ? "完成です! 🎉" : "ヒントを作れませんでした。"
            return
        }
        hint = next
        hintStage = 1
        message = nil
    }

    private func clearHint() { hint = nil; hintStage = 0 }

    // MARK: 写真の読み取り

    func recognize(_ image: CGImage, quad: BoardRecognizer.Quad? = nil) {
        isRecognizing = true
        Task.detached(priority: .userInitiated) {
            let detailed = BoardRecognizer.recognizeDetailed(image, quad: quad)
            // 矛盾(解がない)があれば、次点の候補で読み違いを直す
            let fix = BoardCorrector.correct(detailed.board, alternatives: detailed.alternatives)
            let result = fix?.board ?? detailed.board
            let uncertain = detailed.uncertain.union(fix?.changed ?? [])
            await MainActor.run {
                self.isRecognizing = false
                self.pushHistory()
                self.board = result
                self.uncertain = uncertain
                self.given = []
                self.isSetup = true
                self.selected = nil
                self.clearHint()
                let count = result.cells.filter { $0 != 0 }.count
                let doubt = uncertain.count
                self.message = count == 0
                    ? "数字を読み取れませんでした。盤面全体が写るように撮り直してください。"
                    : fix != nil
                        ? "\(count)個の数字を読み取り、矛盾があったため\(fix!.changed.count)個を自動で直しました。オレンジのマスを確認してください。"
                    : doubt == 0
                        ? "\(count)個の数字を読み取りました。違っているマスをタップして直したら「開始」を押してください。"
                        : "\(count)個の数字を読み取りました。オレンジのマス(\(doubt)個)は自信がないので、タップして確認してください。"
                self.save()
            }
        }
    }

    // MARK: 履歴と自動保存

    private var snapshot: GameSnapshot {
        GameSnapshot(cells: board.cells, given: given.sorted(), isSetup: isSetup)
    }

    private func apply(_ s: GameSnapshot) {
        board = Board(cells: s.cells)
        given = Set(s.given)
        isSetup = s.isSetup
        selected = nil
    }

    private func pushHistory() {
        let now = snapshot
        if history.last == now { return }
        history.append(now)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
    }

    /// 操作のたびに一覧へ保存する。アプリを閉じても、次に開いたとき続きから再開できる。
    private func save() {
        store?.update(gameID, snapshot: snapshot, history: history)
    }
}
