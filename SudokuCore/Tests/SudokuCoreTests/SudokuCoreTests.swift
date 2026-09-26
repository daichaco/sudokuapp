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

@Test func candidates() throws {
    let b = try #require(Board(string: easy))
    #expect(b.candidates(at: 2) == [1, 2, 4])   // 1行3列(0始まり2)
    #expect(b.candidates(at: 0).isEmpty)        // 埋まっているマス
}
