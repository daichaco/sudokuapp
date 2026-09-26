import PhotosUI
import SwiftUI

struct GameView: View {
    @Bindable var vm: GameViewModel
    /// 開いた直後に自動で行う操作(新しい盤面を「撮影」「写真」から始めた場合)。
    var start: StartAction?

    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var didStart = false
    /// 撮影または選んだ写真。角を調整する画面で使う。
    @State private var pendingImage: PendingImage?

    var body: some View {
        VStack(spacing: 12) {
            header
            BoardView(vm: vm)
                .padding(.horizontal, 8)
            infoPanel
            numberPad
            actionBar
        }
        .padding(.vertical, 8)
        .overlay {
            if vm.isRecognizing {
                ProgressView("読み取り中…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                onImage: { image in showCamera = false; pendingImage = PendingImage(image: image) },
                onCancel: { showCamera = false }
            ).ignoresSafeArea()
        }
        .fullScreenCover(item: $pendingImage) { pending in
            CornerEditorView(
                image: pending.image,
                onCancel: { pendingImage = nil },
                onConfirm: { quad in
                    pendingImage = nil
                    vm.recognize(pending.image, quad: quad)
                }
            )
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didStart else { return }
            didStart = true
            switch start {
            case .camera: showCamera = true
            case .photo: showPhotoPicker = true
            default: break
            }
        }
    }

    // MARK: 部品

    private var header: some View {
        HStack(spacing: 8) {
            Text(vm.isSetup ? "問題を入力" : "プレイ中")
                .font(.headline)
                .lineLimit(1)
            Spacer()
            // ボタンが増えても折り返さないよう、「戻す」はアイコンだけにする
            Button { vm.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!vm.canUndo)
                .accessibilityLabel("戻す")
            if vm.isSetup {
                if CameraPicker.isAvailable {
                    Button { showCamera = true } label: { Label("撮影", systemImage: "camera").lineLimit(1) }
                }
                Button { showPhotoPicker = true } label: { Label("写真", systemImage: "photo").lineLimit(1) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .buttonStyle(.bordered)
        .padding(.horizontal)
    }

    private var infoPanel: some View {
        Text(vm.hintPanelText ?? (vm.isSetup ? "マスをタップして数字を入力、または撮影・写真で読み取ります。" : "マスをタップして数字を入力。困ったらヒントを使えます。"))
            .font(.callout)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
    }

    private var numberPad: some View {
        HStack(spacing: 6) {
            ForEach(1...9, id: \.self) { d in
                Button("\(d)") { vm.input(d) }
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            Button { vm.erase() } label: { Image(systemName: "delete.left") }
                .frame(width: 44, height: 44)
                .background(.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 8)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            if vm.isSetup {
                Button("開始") { vm.startGame() }.buttonStyle(.borderedProminent)
                Button("解答を見る") { vm.showSolution() }.buttonStyle(.bordered)
                Button("全消去", role: .destructive) { vm.clearAll() }.buttonStyle(.bordered)
            } else {
                Button(vm.hintButtonTitle) { vm.hintTapped() }.buttonStyle(.borderedProminent)
                Toggle("候補", isOn: $vm.showCandidates).toggleStyle(.button)
                Toggle("間違い", isOn: $vm.showMistakes).toggleStyle(.button)
                Menu("その他") {
                    Button("問題を修正") { vm.editProblem() }
                    Button("最初からやり直す") { vm.restart() }
                    Button("解答を見る") { vm.showSolution() }
                    Button("新しい問題(全消去)", role: .destructive) { vm.clearAll() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }

    // MARK: 読み込み

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let cg = UIImage(data: data)?.uprightCGImage {
                pendingImage = PendingImage(image: cg)
            } else {
                vm.message = "写真を読み込めませんでした。"
            }
            photoItem = nil
        }
    }
}

struct PendingImage: Identifiable {
    let id = UUID()
    let image: CGImage
}

import SudokuCore
enum SampleBoard {
    static let easy = Board(string: "530070000600195000098000060800060003400803001700020006060000280000419005000080079")
}
