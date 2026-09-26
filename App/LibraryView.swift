import SudokuCore
import SwiftUI

/// 新しい盤面を始めるときの入力方法。
enum StartAction: Hashable {
    case camera, photo, manual
}

/// 盤面の一覧。続きから再開する、完成した盤面を見返す、新しい盤面を始める。
struct LibraryView: View {
    @State private var store = GameStore()
    @State private var path: [Route] = []
    @State private var showNewMenu = false

    struct Route: Hashable {
        let id: UUID
        let start: StartAction?
    }

    private var inProgress: [GameRecord] { store.sorted.filter { $0.status != .completed && !$0.isEmpty } }
    private var completed: [GameRecord] { store.sorted.filter { $0.status == .completed } }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button { showNewMenu = true } label: {
                        Label("新しい盤面を始める", systemImage: "plus.circle.fill").font(.headline)
                    }
                }
                if !inProgress.isEmpty {
                    Section("続きから") { ForEach(inProgress) { row($0) } }
                }
                if !completed.isEmpty {
                    Section("完成した盤面") { ForEach(completed) { row($0) } }
                }
                if inProgress.isEmpty && completed.isEmpty {
                    Section {
                        Text("盤面はまだありません。「新しい盤面を始める」から、写真で読み取るか、手で入力して始めましょう。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("盤面一覧")
            .navigationDestination(for: Route.self) { route in
                GameContainer(route: route, store: store)
            }
            .confirmationDialog("新しい盤面", isPresented: $showNewMenu, titleVisibility: .visible) {
                if CameraPicker.isAvailable { Button("カメラで撮影") { start(.camera) } }
                Button("写真から読み取る") { start(.photo) }
                Button("手で入力する") { start(.manual) }
                Button("キャンセル", role: .cancel) {}
            }
            .onChange(of: path) { _, new in
                if new.isEmpty { store.removeEmptyRecords() }    // 入力せずに戻った盤面は残さない
            }
            .onAppear { openSampleIfRequested() }
        }
    }

    private func row(_ r: GameRecord) -> some View {
        Button { path.append(Route(id: r.id, start: nil)) } label: {
            HStack(spacing: 12) {
                MiniBoardView(snapshot: r.snapshot).frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.semibold))
                    Text(statusText(r)).font(.footnote).foregroundStyle(.secondary)
                    Text("更新: " + r.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                if r.status == .completed { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
            }
        }
        .foregroundStyle(.primary)
        .swipeActions {
            Button("削除", role: .destructive) { store.delete(r.id) }
        }
    }

    private func statusText(_ r: GameRecord) -> String {
        switch r.status {
        case .setup: "問題を入力中(\(r.filledCount)マス)"
        case .playing: "プレイ中 — 残り\(81 - r.filledCount)マス"
        case .completed: "完成"
        }
    }

    private func start(_ action: StartAction) {
        let r = store.create()
        path.append(Route(id: r.id, start: action))
    }

    /// 起動引数 -sample のときだけ、サンプル問題を開始した状態で開く(動作確認用)。
    private func openSampleIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-sample"), path.isEmpty,
              let b = SampleBoard.easy else { return }
        var r = store.create()
        r.snapshot = GameSnapshot(cells: b.cells, given: (0..<81).filter { b.cells[$0] != 0 }, isSetup: false)
        store.update(r.id, snapshot: r.snapshot, history: [])
        path.append(Route(id: r.id, start: nil))
    }
}

/// 一覧から開く1盤面の画面。ここで作った状態管理は、その盤面を閉じるまで保たれる。
private struct GameContainer: View {
    let route: LibraryView.Route
    @State private var vm: GameViewModel

    init(route: LibraryView.Route, store: GameStore) {
        self.route = route
        _vm = State(initialValue: GameViewModel(record: store.record(route.id) ?? GameRecord(), store: store))
    }

    var body: some View {
        GameView(vm: vm, start: route.start)
    }
}

/// 一覧に並べる小さな盤面。
struct MiniBoardView: View {
    let snapshot: GameSnapshot

    var body: some View {
        Canvas { ctx, size in
            let cell = size.width / 9
            var thin = Path(), thick = Path()
            for i in 0...9 {
                let p = CGFloat(i) * cell
                if i % 3 == 0 {
                    thick.move(to: CGPoint(x: p, y: 0)); thick.addLine(to: CGPoint(x: p, y: size.height))
                    thick.move(to: CGPoint(x: 0, y: p)); thick.addLine(to: CGPoint(x: size.width, y: p))
                } else {
                    thin.move(to: CGPoint(x: p, y: 0)); thin.addLine(to: CGPoint(x: p, y: size.height))
                    thin.move(to: CGPoint(x: 0, y: p)); thin.addLine(to: CGPoint(x: size.width, y: p))
                }
            }
            ctx.stroke(thin, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)
            ctx.stroke(thick, with: .color(.primary), lineWidth: 1.2)
            let given = Set(snapshot.given)
            for i in 0..<81 where snapshot.cells[i] != 0 {
                let isGiven = given.contains(i) || snapshot.isSetup
                let text = Text("\(snapshot.cells[i])")
                    .font(.system(size: cell * 0.75, weight: isGiven ? .bold : .regular, design: .rounded))
                    .foregroundColor(isGiven ? .primary : .blue)
                ctx.draw(text, at: CGPoint(x: (CGFloat(i % 9) + 0.5) * cell, y: (CGFloat(i / 9) + 0.5) * cell))
            }
        }
        .background(Color(.systemBackground))
        .accessibilityHidden(true)
    }
}
