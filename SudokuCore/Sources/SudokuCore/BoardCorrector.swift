/// 読み違えたときの次点の数字と、その「悪さ」(小さいほど有力)。
public struct DigitCandidate: Equatable, Sendable {
    public var digit: Int
    public var cost: Float
    public init(digit: Int, cost: Float) { self.digit = digit; self.cost = cost }
}

/// 読み取り結果に矛盾がある(解がない)とき、数字の読み違いを次点の候補で直す。
///
/// 正しい数独の問題は解がちょうど1つなので、数字を1つ読み違えると、たいてい解がなくなる。
/// そこで、次点の候補に置き換えて「解がちょうど1つ」になる組み合わせを探す。
public enum BoardCorrector {
    public struct Fix: Equatable, Sendable {
        public var board: Board
        /// 置き換えたマスの番号(0..<81)。
        public var changed: [Int]
    }

    private struct Option { var index: Int; var digit: Int; var cost: Float }

    /// - Parameters:
    ///   - alternatives: 各マスの次点の候補(近い順)。`BoardRecognizer.recognizeDetailed` の結果。
    ///   - maxChanges: 直すマスの上限(1 か 2)。
    /// - Returns: すでに解けるとき、または直し方が見つからないときは nil。
    public static func correct(_ board: Board, alternatives: [Int: [DigitCandidate]],
                               maxChanges: Int = 2) -> Fix? {
        // すでに解がある(一意でなくても)なら、余計なことをしない
        if Solver.countSolutions(board, limit: 1) >= 1 { return nil }

        let all = alternatives.flatMap { index, cands in
            cands.filter { board.cells[index] != 0 && $0.digit != board.cells[index] }
                 .map { Option(index: index, digit: $0.digit, cost: $0.cost) }
        }.sorted { $0.cost < $1.cost }

        // 1マスだけの置き換え。解がちょうど1つになるもののうち、いちばん有力なもの。
        // 行・列・ブロックに重複がある(=確実に読み違いがある)場合は、数字が少なくて解が複数ある盤面のために、
        // 解がちょうど1つでなくても「重複が消えて解ける」ものを次善として使う。
        let duplicated = !board.isConsistent
        var best: (cost: Float, fix: Fix)?
        var solvable: (cost: Float, fix: Fix)?
        for o in all.prefix(60) {
            var b = board
            b.cells[o.index] = o.digit
            let n = Solver.countSolutions(b, limit: 2)
            if n == 1, best == nil || o.cost < best!.cost { best = (o.cost, Fix(board: b, changed: [o.index])) }
            if n >= 1, duplicated, solvable == nil || o.cost < solvable!.cost { solvable = (o.cost, Fix(board: b, changed: [o.index])) }
        }
        if let best { return best.fix }
        if let solvable { return solvable.fix }
        guard maxChanges >= 2 else { return nil }

        // 2マスの置き換え(候補が多いと数が増えるので、有力なものだけ)
        let pool = Array(all.prefix(24))
        for i in 0..<pool.count {
            for j in (i + 1)..<pool.count where pool[i].index != pool[j].index {
                let cost = pool[i].cost + pool[j].cost
                if let best, cost >= best.cost { continue }
                var b = board
                b.cells[pool[i].index] = pool[i].digit
                b.cells[pool[j].index] = pool[j].digit
                guard Solver.countSolutions(b, limit: 2) == 1 else { continue }
                best = (cost, Fix(board: b, changed: [pool[i].index, pool[j].index].sorted()))
            }
        }
        return best?.fix
    }
}
