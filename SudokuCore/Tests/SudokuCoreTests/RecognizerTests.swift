#if canImport(Vision)
import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import SudokuCore

/// 数独の盤面を画像として描画する(回転・余白つき)。
func renderBoard(_ board: Board, rotationDegrees: Double = 0) -> CGImage {
    let size = 1200
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.93, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.translateBy(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
    ctx.rotate(by: rotationDegrees * .pi / 180)
    ctx.translateBy(x: -450, y: -450)

    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 900))
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
    for i in 0...9 {
        ctx.setLineWidth(i % 3 == 0 ? 5 : 2)
        ctx.move(to: CGPoint(x: i * 100, y: 0)); ctx.addLine(to: CGPoint(x: i * 100, y: 900))
        ctx.move(to: CGPoint(x: 0, y: i * 100)); ctx.addLine(to: CGPoint(x: 900, y: i * 100))
        ctx.strokePath()
    }
    let font = CTFontCreateWithName("Helvetica" as CFString, 64, nil)
    for r in 0..<9 {
        for c in 0..<9 where board[r, c] != 0 {
            let attr = NSAttributedString(string: "\(board[r, c])", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.05, alpha: 1)])
            let line = CTLineCreateWithAttributedString(attr)
            let b = CTLineGetBoundsWithOptions(line, [])
            ctx.textPosition = CGPoint(x: CGFloat(c * 100) + 50 - b.width / 2 - b.minX,
                                       y: CGFloat((8 - r) * 100) + 50 - b.height / 2 - b.minY)
            CTLineDraw(line, ctx)
        }
    }
    return ctx.makeImage()!
}

func accuracy(_ a: Board, _ b: Board) -> Double {
    Double((0..<81).filter { a.cells[$0] == b.cells[$0] }.count) / 81
}

@Test func recognizesRenderedBoard() throws {
    let expected = try #require(Board(string: easy))
    let got = BoardRecognizer.recognize(renderBoard(expected))
    let acc = accuracy(got, expected)
    print("recognition accuracy (straight):", acc)
    #expect(acc >= 0.98)
}

@Test func recognizesRotatedBoard() throws {
    let expected = try #require(Board(string: easy))
    let got = BoardRecognizer.recognize(renderBoard(expected, rotationDegrees: 6))
    let acc = accuracy(got, expected)
    print("recognition accuracy (rotated 6deg):", acc)
    #expect(acc >= 0.98)
}
#endif
