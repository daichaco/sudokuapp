public enum Solver {
    /// 解を1つ返す。矛盾があるか解がなければ nil。
    public static func solve(_ board: Board) -> Board? {
        guard board.isConsistent else { return nil }
        var b = board
        return search(&b) ? b : nil
    }

    /// 解の個数を上限 limit まで数える(一意性の確認用)。
    public static func countSolutions(_ board: Board, limit: Int = 2) -> Int {
        guard board.isConsistent else { return 0 }
        var b = board
        var count = 0
        countSearch(&b, limit: limit, count: &count)
        return count
    }

    /// 候補が最も少ないマスから試すバックトラッキング。
    private static func pickCell(_ b: Board) -> (index: Int, mask: Int)?? {
        var best: (Int, Int)?
        var bestCount = 10
        for i in 0..<81 where b.cells[i] == 0 {
            let m = b.candidateMask(at: i)
            let n = m.nonzeroBitCount
            if n == 0 { return .some(nil) }   // 行き詰まり
            if n < bestCount { best = (i, m); bestCount = n }
        }
        guard let best else { return nil }    // 全マス埋まっている
        return .some(best)
    }

    private static func search(_ b: inout Board) -> Bool {
        switch pickCell(b) {
        case .none: return true
        case .some(.none): return false
        case .some(.some(let (i, mask))):
            for d in 1...9 where mask & (1 << d) != 0 {
                b.cells[i] = d
                if search(&b) { return true }
            }
            b.cells[i] = 0
            return false
        }
    }

    private static func countSearch(_ b: inout Board, limit: Int, count: inout Int) {
        switch pickCell(b) {
        case .none: count += 1
        case .some(.none): return
        case .some(.some(let (i, mask))):
            for d in 1...9 where mask & (1 << d) != 0 {
                b.cells[i] = d
                countSearch(&b, limit: limit, count: &count)
                if count >= limit { break }
            }
            b.cells[i] = 0
        }
    }
}
