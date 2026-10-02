import Testing
@testable import SudokuCore

let easy = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
let solved = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
// 論理だけでは詰まりやすい難問
let hard = "800000000003600000070090200050007000000045700000100030001000068008500010090000400"

@Test func solvesEasy() throws {
    let b = try #require(Board(string: easy))
    let s = try #require(Solver.solve(b))
    #expect(s == Board(string: solved))
}

@Test func solvesHard() throws {
    let b = try #require(Board(string: hard))
    let s = try #require(Solver.solve(b))
    #expect(s.isComplete)
}

@Test func rejectsInvalid() throws {
    var b = try #require(Board(string: easy))
    b[0, 2] = 5   // 1行目に 5 が重複
    #expect(Solver.solve(b) == nil)
}

@Test func uniqueness() throws {
    let b = try #require(Board(string: easy))
    #expect(Solver.countSolutions(b) == 1)
    #expect(Solver.countSolutions(Board()) == 2)   // 空盤面は上限まで
}

@Test func hintIsCorrectAndExplained() throws {
    let b = try #require(Board(string: easy))
    let solution = try #require(Solver.solve(b))
    let h = try #require(HintEngine.nextHint(for: b))
    #expect(b.cells[h.index] == 0)
    #expect(solution.cells[h.index] == h.value)
    #expect(!h.explanation.isEmpty)
}

@Test func hintsSolveWholePuzzle() throws {
    // ヒントを繰り返し適用するだけで完成し、常に正解の手を示す
    var b = try #require(Board(string: easy))
    let solution = try #require(Solver.solve(b))
    var steps = 0
    while let h = HintEngine.nextHint(for: b) {
        #expect(solution.cells[h.index] == h.value)
        b.cells[h.index] = h.value
        steps += 1
    }
    #expect(b == solution)
    #expect(steps == 81 - easy.filter { $0 != "0" }.count)
}

@Test func hintsWorkOnHardPuzzle() throws {
    var b = try #require(Board(string: hard))
    let solution = try #require(Solver.solve(b))
    while let h = HintEngine.nextHint(for: b) {
        #expect(solution.cells[h.index] == h.value)
        b.cells[h.index] = h.value
    }
    #expect(b == solution)
}

@Test func detectsMistakes() throws {
    let puzzle = try #require(Board(string: easy))
    let given = Set((0..<81).filter { puzzle.cells[$0] != 0 })
    var b = puzzle
    let solution = try #require(Solver.solve(puzzle))
    let target = (0..<81).first { puzzle.cells[$0] == 0 }!
    #expect(HintEngine.mistakes(in: b, given: given).isEmpty)
    b.cells[target] = solution.cells[target] % 9 + 1   // わざと間違える
    #expect(HintEngine.mistakes(in: b, given: given).contains(target))
    b.cells[target] = solution.cells[target]
    #expect(HintEngine.mistakes(in: b, given: given).isEmpty)
}

/// 解が複数ある問題(easy からヒントを減らして作る)と、そのヒントのマス。
private func ambiguousPuzzle() throws -> (puzzle: Board, given: Set<Int>) {
    var b = try #require(Board(string: easy))
    for i in 0..<81 where b.cells[i] != 0 {
        let kept = b.cells[i]
        b.cells[i] = 0
        if Solver.countSolutions(b) > 1 { break }
        if Solver.countSolutions(b) != 1 { b.cells[i] = kept }
    }
    try #require(Solver.countSolutions(b) > 1)
    return (b, Set((0..<81).filter { b.cells[$0] != 0 }))
}

@Test func acceptsAlternativeSolutionOfAmbiguousPuzzle() throws {
    let (puzzle, given) = try ambiguousPuzzle()
    let first = try #require(Solver.solve(puzzle))
    // 見つけた解とは違う数字を置いても、解が成り立つマスを探す
    var alternative: (index: Int, digit: Int)?
    search: for i in 0..<81 where puzzle.cells[i] == 0 {
        for d in 1...9 where d != first.cells[i] {
            var probe = puzzle
            probe.cells[i] = d
            if Solver.countSolutions(probe, limit: 1) > 0 { alternative = (i, d); break search }
        }
    }
    let alt = try #require(alternative)
    var b = puzzle
    b.cells[alt.index] = alt.digit
    #expect(HintEngine.mistakes(in: b, given: given).isEmpty)
}

@Test func stillFlagsImpossibleEntryOfAmbiguousPuzzle() throws {
    let (puzzle, given) = try ambiguousPuzzle()
    // どの解でも入らない数字(置くと解がなくなる数字)を探す
    var impossible: (index: Int, digit: Int)?
    search: for i in 0..<81 where puzzle.cells[i] == 0 {
        for d in puzzle.candidates(at: i) {
            var probe = puzzle
            probe.cells[i] = d
            if Solver.countSolutions(probe, limit: 1) == 0 { impossible = (i, d); break search }
        }
    }
    let bad = try #require(impossible)
    var b = puzzle
    b.cells[bad.index] = bad.digit
    #expect(HintEngine.mistakes(in: b, given: given).contains(bad.index))
}

@Test func stillFlagsDuplicates() throws {
    let puzzle = try #require(Board(string: easy))
    let given = Set((0..<81).filter { puzzle.cells[$0] != 0 })
    var b = puzzle
    let target = (0..<81).first { puzzle.cells[$0] == 0 }!
    b.cells[target] = b.cells[(target / 9) * 9 + (target % 9 == 0 ? 1 : 0)]   // 同じ行の数字を重ねる
    #expect(HintEngine.mistakes(in: b, given: given).contains(target))
}

@Test func candidates() throws {
    let b = try #require(Board(string: easy))
    #expect(b.candidates(at: 2) == [1, 2, 4])   // 1行3列(0始まり2)
    #expect(b.candidates(at: 0).isEmpty)        // 埋まっているマス
}

// MARK: 読み違いの自動補正

@Test func correctorFixesSingleMisread() throws {
    let truth = try #require(Board(string: easy))
    var read = truth
    // 4 を 6 と読み違えた、という状況を作る(同じ行に 6 がなければ矛盾しないので、行に 6 がある位置を選ぶ)
    let idx = try #require((0..<81).first { i in truth.cells[i] == 4 })
    read.cells[idx] = 6
    let alternatives: [Int: [DigitCandidate]] = [idx: [DigitCandidate(digit: 4, cost: 3), DigitCandidate(digit: 1, cost: 40)]]
    let fix = try #require(BoardCorrector.correct(read, alternatives: alternatives))
    #expect(fix.board == truth)
    #expect(fix.changed == [idx])
}

@Test func correctorPicksTheLikelierOfSeveralFixes() throws {
    let truth = try #require(Board(string: easy))
    var read = truth
    let idx = try #require((0..<81).first { truth.cells[$0] == 4 })
    read.cells[idx] = 6
    // 次点に、正しくない候補(1)のほうが有力な形で並んでいても、解がちょうど1つになるものを選ぶ
    let alternatives: [Int: [DigitCandidate]] = [idx: [DigitCandidate(digit: 1, cost: 1), DigitCandidate(digit: 4, cost: 5)]]
    let fix = try #require(BoardCorrector.correct(read, alternatives: alternatives))
    #expect(fix.board == truth)
}

@Test func correctorFixesTwoMisreads() throws {
    let truth = try #require(Board(string: easy))
    var read = truth
    let fours = (0..<81).filter { truth.cells[$0] == 4 }
    let a = fours[0], b = fours[1]
    read.cells[a] = 6; read.cells[b] = 9
    let alternatives: [Int: [DigitCandidate]] = [a: [DigitCandidate(digit: 4, cost: 2)], b: [DigitCandidate(digit: 4, cost: 4)]]
    let fix = try #require(BoardCorrector.correct(read, alternatives: alternatives))
    #expect(fix.board == truth)
    #expect(Set(fix.changed) == [a, b])
}

@Test func correctorLeavesSolvableBoardAlone() throws {
    let truth = try #require(Board(string: easy))
    let idx = try #require((0..<81).first { truth.cells[$0] == 4 })
    let alternatives: [Int: [DigitCandidate]] = [idx: [DigitCandidate(digit: 6, cost: 1)]]
    #expect(BoardCorrector.correct(truth, alternatives: alternatives) == nil)
}

@Test func correctorGivesUpWithoutAGoodCandidate() throws {
    let truth = try #require(Board(string: easy))
    var read = truth
    let idx = try #require((0..<81).first { truth.cells[$0] == 4 })
    read.cells[idx] = 6
    // 正解の 4 が候補に無いなら、無理に直さない
    let alternatives: [Int: [DigitCandidate]] = [idx: [DigitCandidate(digit: 2, cost: 5)]]
    #expect(BoardCorrector.correct(read, alternatives: alternatives) == nil)
}

@Test func correctorFixesDuplicateOnSparseBoard() throws {
    // 数字が少なく解が複数ある盤面でも、重複(6が2つ)があれば、次点の候補で直す
    var truth = Board()
    for (i, v) in [(1, 5), (2, 8), (10, 1), (11, 7), (12, 6), (20, 2), (21, 3), (56, 9), (65, 4)] { truth.cells[i] = v }
    var read = truth
    read.cells[56] = 6; read.cells[58] = 6            // 同じ行に 6 が2つ(56 は本当は 9)
    let fix = try #require(BoardCorrector.correct(read, alternatives: [56: [DigitCandidate(digit: 9, cost: 2)]]))
    #expect(fix.changed == [56])
    #expect(fix.board.cells[56] == 9)
}
