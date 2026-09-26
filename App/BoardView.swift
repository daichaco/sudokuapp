import SudokuCore
import SwiftUI

struct BoardView: View {
    let vm: GameViewModel

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 9
            ZStack(alignment: .topLeading) {
                ForEach(0..<81, id: \.self) { i in
                    CellView(vm: vm, index: i)
                        .frame(width: cell, height: cell)
                        .offset(x: CGFloat(i % 9) * cell, y: CGFloat(i / 9) * cell)
                        .onTapGesture { vm.select(i) }
                }
                Path { p in
                    for i in 0...9 {
                        p.move(to: CGPoint(x: CGFloat(i) * cell, y: 0))
                        p.addLine(to: CGPoint(x: CGFloat(i) * cell, y: side))
                        p.move(to: CGPoint(x: 0, y: CGFloat(i) * cell))
                        p.addLine(to: CGPoint(x: side, y: CGFloat(i) * cell))
                    }
                }
                .stroke(Color.primary.opacity(0.35), lineWidth: 0.5)
                .allowsHitTesting(false)
                Path { p in
                    for i in stride(from: 0, through: 9, by: 3) {
                        p.move(to: CGPoint(x: CGFloat(i) * cell, y: 0))
                        p.addLine(to: CGPoint(x: CGFloat(i) * cell, y: side))
                        p.move(to: CGPoint(x: 0, y: CGFloat(i) * cell))
                        p.addLine(to: CGPoint(x: side, y: CGFloat(i) * cell))
                    }
                }
                .stroke(Color.primary, lineWidth: 2)
                .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct CellView: View {
    let vm: GameViewModel
    let index: Int

    var body: some View {
        let value = vm.board.cells[index]
        let isGiven = vm.given.contains(index)
        ZStack {
            background
            if value != 0 {
                Text("\(value)")
                    .font(.system(size: 28, weight: isGiven ? .bold : .regular, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(isGiven || vm.isSetup ? Color.primary : Color.blue)
            } else if vm.showCandidates && !vm.isSetup {
                candidateGrid
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel("\(index / 9 + 1)行\(index % 9 + 1)列 \(value == 0 ? "空白" : "\(value)")")
    }

    private var background: some View {
        let sel = vm.selected
        let color: Color = {
            if vm.mistakes.contains(index) { return .red.opacity(0.30) }
            if vm.hintTarget == index { return .green.opacity(0.45) }
            if vm.hintRelated.contains(index) { return .yellow.opacity(0.35) }
            if sel == index { return .blue.opacity(0.30) }
            if let sel, vm.board.cells[sel] != 0, vm.board.cells[sel] == vm.board.cells[index] {
                return .blue.opacity(0.14)
            }
            if let sel, Board.peers[sel].contains(index) { return .blue.opacity(0.06) }
            return .clear
        }()
        return color
    }

    private var candidateGrid: some View {
        let cands = Set(vm.board.candidates(at: index))
        return VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { c in
                        let d = r * 3 + c + 1
                        Text(cands.contains(d) ? "\(d)" : " ")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(2)
    }
}
