/// 「次の1手」のヒント。
public struct Hint: Equatable, Sendable {
    public enum Technique: Equatable, Sendable {
        case nakedSingle        // このマスに入る数字が1つしかない
        case hiddenSingle       // ユニット内でこの数字を置けるマスが1つしかない
        case fromSolution       // 論理では決まらないので解から1マス示す
    }

    public let index: Int
    public let value: Int
    public let technique: Technique
    /// 理由の説明(日本語)。
    public let explanation: String
    /// 根拠として強調表示するマス(ユニット全体や関連マス)。
    public let relatedIndices: [Int]

    public var row: Int { Board.row(of: index) }
    public var col: Int { Board.col(of: index) }
}

public enum HintEngine {
    /// 次の1手を返す。すでに完成、または解けない盤面なら nil。
    /// 易しい手(ネイキッドシングル → ヒドゥンシングル)を優先し、なければ解から示す。
    public static func nextHint(for board: Board) -> Hint? {
        guard board.isConsistent, !board.cells.isEmpty, board.cells.contains(0) else { return nil }
        if let h = nakedSingle(board) { return h }
        if let h = hiddenSingle(board) { return h }
        guard let solution = Solver.solve(board) else { return nil }
        // 候補が最も少ないマスを示す
        let i = (0..<81).filter { board.cells[$0] == 0 }
            .min { board.candidates(at: $0).count < board.candidates(at: $1).count }!
        return Hint(
            index: i, value: solution.cells[i], technique: .fromSolution,
            explanation: "この盤面は単純な消去では決まらないため、全体を解いて確認しました。\(cellName(i))には \(solution.cells[i]) が入ります。",
            relatedIndices: [])
    }

    private static func nakedSingle(_ b: Board) -> Hint? {
        for i in 0..<81 where b.cells[i] == 0 {
            let c = b.candidates(at: i)
            if c.count == 1 {
                let related = Board.peers[i].filter { b.cells[$0] != 0 }
                return Hint(
                    index: i, value: c[0], technique: .nakedSingle,
                    explanation: "\(cellName(i))は、同じ行・列・ブロックにある数字を除くと、入る数字が \(c[0]) だけになります。",
                    relatedIndices: related)
            }
        }
        return nil
    }

    private static func hiddenSingle(_ b: Board) -> Hint? {
        // ブロック → 行 → 列 の順に探す(ブロックが一番見つけやすい)
        let ordered = Board.units.filter { $0.kind == .box }
            + Board.units.filter { $0.kind == .row }
            + Board.units.filter { $0.kind == .column }
        for u in ordered {
            for d in 1...9 where !u.indices.contains(where: { b.cells[$0] == d }) {
                let spots = u.indices.filter { b.cells[$0] == 0 && b.candidateMask(at: $0) & (1 << d) != 0 }
                if spots.count == 1 {
                    let i = spots[0]
                    return Hint(
                        index: i, value: d, technique: .hiddenSingle,
                        explanation: "\(u.name)の中で \(d) を入れられるマスは、\(cellName(i))だけです(他のマスは同じ行・列・ブロックにすでに \(d) があります)。",
                        relatedIndices: u.indices)
                }
            }
        }
        return nil
    }

    /// 入力済みの数字のうち、解と食い違うマスのインデックス。
    /// 解が一意に決まらない/存在しない場合は、重複しているマスを返す。
    public static func mistakes(in board: Board, given: Set<Int> = []) -> [Int] {
        var wrong = Set<Int>()
        for u in Board.units {
            var byValue: [Int: [Int]] = [:]
            for i in u.indices where board.cells[i] != 0 { byValue[board.cells[i], default: []].append(i) }
            for (_, idxs) in byValue where idxs.count > 1 { wrong.formUnion(idxs) }
        }
        // 元の問題(given)から解を求め、ユーザー入力と比較
        var puzzle = board
        for i in 0..<81 where !given.contains(i) { puzzle.cells[i] = 0 }
        if !given.isEmpty, let solution = Solver.solve(puzzle) {
            for i in 0..<81 where !given.contains(i) && board.cells[i] != 0 && board.cells[i] != solution.cells[i] {
                wrong.insert(i)
            }
        }
        return wrong.sorted()
    }

    static func cellName(_ i: Int) -> String { "\(Board.row(of: i) + 1)行\(Board.col(of: i) + 1)列のマス" }
}
