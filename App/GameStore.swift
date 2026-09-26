import Foundation
import Observation

/// 1つの盤面(問題と、その途中経過)。
struct GameRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var updatedAt = Date()
    var snapshot = GameSnapshot(cells: Array(repeating: 0, count: 81), given: [], isSetup: true)
    /// 「戻す」用の履歴(古い順)。
    var history: [GameSnapshot] = []

    var filledCount: Int { snapshot.cells.filter { $0 != 0 }.count }
    /// 問題として確定した数字の数(入力中は 0)。
    var givenCount: Int { snapshot.given.count }
    var isEmpty: Bool { filledCount == 0 }

    enum Status { case setup, playing, completed }

    var status: Status {
        if snapshot.isSetup { return .setup }
        return snapshot.cells.allSatisfy({ $0 != 0 }) && isValidComplete ? .completed : .playing
    }

    /// 全マスが埋まっていて、行・列・ブロックに重複がない。
    private var isValidComplete: Bool {
        let c = snapshot.cells
        func ok(_ idx: [Int]) -> Bool { Set(idx.map { c[$0] }).count == 9 }
        for i in 0..<9 {
            if !ok((0..<9).map { i * 9 + $0 }) || !ok((0..<9).map { $0 * 9 + i }) { return false }
            let r0 = i / 3 * 3, c0 = i % 3 * 3
            if !ok((0..<9).map { (r0 + $0 / 3) * 9 + c0 + $0 % 3 }) { return false }
        }
        return true
    }
}

/// 盤面の一覧を端末に保存する。操作のたびに書き出すので、アプリを閉じても続きから再開できる。
@MainActor
@Observable
final class GameStore {
    private(set) var records: [GameRecord] = []
    private let fileURL: URL?

    /// `fileURL` に nil を渡すと保存しない(テスト用)。
    init(fileURL: URL? = GameStore.defaultURL) {
        self.fileURL = fileURL
        load()
        migrateLegacySave()
    }

    nonisolated static var defaultURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true).appendingPathComponent("games.json")
    }

    /// 新しい順。
    var sorted: [GameRecord] { records.sorted { $0.updatedAt > $1.updatedAt } }

    func record(_ id: UUID) -> GameRecord? { records.first { $0.id == id } }

    @discardableResult
    func create() -> GameRecord {
        let r = GameRecord()
        records.append(r)
        save()
        return r
    }

    func update(_ id: UUID, snapshot: GameSnapshot, history: [GameSnapshot]) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].snapshot = snapshot
        records[i].history = history
        records[i].updatedAt = Date()
        save()
    }

    func delete(_ id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    /// 何も入力されないまま残った盤面を片付ける(「新しい盤面」を作って戻っただけの場合など)。
    func removeEmptyRecords(except keep: UUID? = nil) {
        let before = records.count
        records.removeAll { $0.isEmpty && $0.snapshot.isSetup && $0.id != keep }
        if records.count != before { save() }
    }

    // MARK: 保存

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([GameRecord].self, from: data) else { return }
        records = decoded.filter { $0.snapshot.cells.count == 81 && $0.history.allSatisfy { $0.cells.count == 81 } }
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 以前のバージョンは1つの盤面だけを UserDefaults に保存していた。あれば一覧に移す。
    private func migrateLegacySave() {
        struct Legacy: Codable { var current: GameSnapshot; var history: [GameSnapshot] }
        let key = "sudokuhelper.savedGame.v1"
        guard fileURL != nil, let data = UserDefaults.standard.data(forKey: key),
              let legacy = try? JSONDecoder().decode(Legacy.self, from: data),
              legacy.current.cells.count == 81 else { return }
        UserDefaults.standard.removeObject(forKey: key)
        guard legacy.current.cells.contains(where: { $0 != 0 }) else { return }
        var r = GameRecord()
        r.snapshot = legacy.current
        r.history = legacy.history.filter { $0.cells.count == 81 }
        records.append(r)
        save()
    }
}
