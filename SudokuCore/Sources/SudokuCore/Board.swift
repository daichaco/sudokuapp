/// 9x9 の数独盤面。0 が空きマス。
public struct Board: Equatable, Sendable {
    public var cells: [Int]

    public init(cells: [Int] = Array(repeating: 0, count: 81)) {
        precondition(cells.count == 81)
        self.cells = cells
    }

    /// 81文字の文字列(1-9 が数字、0 か . が空き)から作る。それ以外の文字は無視。
    public init?(string: String) {
        let digits = string.compactMap { ch -> Int? in
            if ch == "." { return 0 }
            return ch.wholeNumberValue
        }
        guard digits.count == 81 else { return nil }
        self.init(cells: digits)
    }

    public subscript(row: Int, col: Int) -> Int {
        get { cells[row * 9 + col] }
        set { cells[row * 9 + col] = newValue }
    }

    public static func row(of index: Int) -> Int { index / 9 }
    public static func col(of index: Int) -> Int { index % 9 }
    public static func box(of index: Int) -> Int { index / 27 * 3 + index % 9 / 3 }

    /// 行・列・ブロックの27ユニット(各9マスのインデックス)。
    public static let units: [Unit] = {
        var result: [Unit] = []
        for i in 0..<9 {
            result.append(Unit(kind: .row, number: i, indices: (0..<9).map { i * 9 + $0 }))
        }
        for i in 0..<9 {
            result.append(Unit(kind: .column, number: i, indices: (0..<9).map { $0 * 9 + i }))
        }
        for b in 0..<9 {
            let r0 = b / 3 * 3, c0 = b % 3 * 3
            let idx = (0..<9).map { (r0 + $0 / 3) * 9 + c0 + $0 % 3 }
            result.append(Unit(kind: .box, number: b, indices: idx))
        }
        return result
    }()

    /// 各マスと同じユニットに属する他のマス(20個)。
    public static let peers: [[Int]] = (0..<81).map { i in
        var set = Set<Int>()
        for u in units where u.indices.contains(i) { set.formUnion(u.indices) }
        set.remove(i)
        return set.sorted()
    }

    /// 埋まっているマスの間に重複がなければ true。
    public var isConsistent: Bool {
        for u in Board.units {
            var seen = Set<Int>()
            for i in u.indices where cells[i] != 0 {
                if !seen.insert(cells[i]).inserted { return false }
            }
        }
        return true
    }

    public var isComplete: Bool { !cells.contains(0) && isConsistent }

    /// 空きマス i に入りうる数字(ビットマスク: bit d が立っていれば d が候補)。
    func candidateMask(at i: Int) -> Int {
        var used = 0
        for p in Board.peers[i] where cells[p] != 0 { used |= 1 << cells[p] }
        return 0x3FE & ~used
    }

    /// マス i の候補数字(埋まっているマスは空)。
    public func candidates(at i: Int) -> [Int] {
        guard cells[i] == 0 else { return [] }
        let m = candidateMask(at: i)
        return (1...9).filter { m & (1 << $0) != 0 }
    }
}

public struct Unit: Sendable {
    public enum Kind: Sendable { case row, column, box }
    public let kind: Kind
    public let number: Int   // 0始まり
    public let indices: [Int]

    public var name: String {
        switch kind {
        case .row: "\(number + 1)行目"
        case .column: "\(number + 1)列目"
        case .box: "ブロック\(number + 1)"
        }
    }
}
