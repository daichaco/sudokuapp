import Observation
import SudokuCore
import SwiftUI

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

    func select(_ i: Int) { selected = i }

    func input(_ digit: Int) {
        guard let i = selected, canEdit(i) else { return }
        board.cells[i] = digit
        clearHint()
        message = nil
    }

    func erase() { input(0) }

    private func canEdit(_ i: Int) -> Bool { isSetup || !given.contains(i) }

    func startGame() {
        guard board.isConsistent else { message = "同じ行・列・ブロックに重複があります。赤いマスを直してください。"; return }
        guard board.cells.contains(where: { $0 != 0 }) else { message = "数字を入力するか、写真を読み取ってください。"; return }
        guard Solver.countSolutions(board) > 0 else { message = "この問題には解がありません。読み取りや入力を確認してください。"; return }
        given = Set((0..<81).filter { board.cells[$0] != 0 })
        isSetup = false
        selected = nil
        clearHint()
        message = nil
    }

    func editProblem() {
        isSetup = true
        clearHint()
        message = nil
    }

    /// 自分で入れた数字だけ消して最初から。
    func restart() {
        for i in 0..<81 where !given.contains(i) { board.cells[i] = 0 }
        clearHint()
        message = nil
    }

    func clearAll() {
        board = Board(); given = []; selected = nil; isSetup = true
        clearHint(); message = nil
    }

    func showSolution() {
        var problem = board
        if !isSetup { for i in 0..<81 where !given.contains(i) { problem.cells[i] = 0 } }
        guard let solution = Solver.solve(problem) else {
            message = "解けませんでした。入力に間違いがないか確認してください。"; return
        }
        board = solution
        clearHint()
        message = "解答を表示しました。"
    }

    func hintTapped() {
        if isSetup { message = "先に「開始」を押して問題を確定してください。"; return }
        if let hint, hintStage >= 2 {
            board.cells[hint.index] = hint.value
            selected = hint.index
            clearHint()
            if board.isComplete { message = "完成です! 🎉" }
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

    func recognize(_ image: CGImage) {
        isRecognizing = true
        Task.detached(priority: .userInitiated) {
            let result = BoardRecognizer.recognize(image)
            await MainActor.run {
                self.isRecognizing = false
                self.board = result
                self.given = []
                self.isSetup = true
                self.selected = nil
                self.clearHint()
                let count = result.cells.filter { $0 != 0 }.count
                self.message = count == 0
                    ? "数字を読み取れませんでした。盤面全体が写るように撮り直してください。"
                    : "\(count)個の数字を読み取りました。違っているマスをタップして直したら「開始」を押してください。"
            }
        }
    }
}
