# SudokuHelper

数独を解くのを手伝う iOS アプリ。紙の数独を撮影して盤面を読み取り、次の1手のヒントを理由つきで教えてくれます。

## 機能

- **盤面の読み取り** — カメラ（実機のみ）または写真から数独を認識（Vision / Core Image）
- **ヒント** — 「次の1手」を、ネイキッドシングル → ヒドゥンシングルの順に易しい手から提示し、理由を日本語で説明。論理で決まらない場合は解から1マスを示します
- **ソルバー** — 盤面の整合性チェックと解の探索

## 構成

| ディレクトリ | 内容 |
| --- | --- |
| `App/` | SwiftUI アプリ本体（`SudokuHelper.xcodeproj` から利用） |
| `SudokuCore/` | ロジックを集めた Swift Package（`Board` / `Solver` / `HintEngine` / `BoardRecognizer`）とテスト |
| `index.html` | ブラウザで遊べる単体の数独（依存なし） |

## 動作環境

- iOS 17 以降 / macOS 14 以降（`SudokuCore`）
- Xcode（Swift 6 ツールチェーン）

## ビルドとテスト

アプリ: `SudokuHelper.xcodeproj` を Xcode で開いて実行します。カメラでのスキャンは実機が必要です。

コアのテスト:

```sh
cd SudokuCore
swift test
```

## Web 版

`index.html` をブラウザで開くだけで動きます。
