# App Store 公開までに、あなたがすること

上から順に進めてください。☐ は未着手です。
私(Claude)が用意したもの: 掲載文 `AppStore/listing-ja.md`、スクリーンショット `AppStore/screenshots/`、プライバシーポリシー `docs/privacy-policy.md`、アイコン、Bundle ID など。

## 0. 先に決めること(すぐ終わる)
- ☐ **公開名義**(アプリの提供者として表示される名前)を決める。個人なら本名になる。Apple Developer Program の登録名がそのまま表示される。
- ☐ 問い合わせ先: プライバシーポリシーは GitHub の Issues にした(メールを載せたい場合だけ変更する)。App Store Connect の審査用連絡先(氏名・電話・メール)は別に必要(公開されない)。
- ☐ **アプリ名**を決める(第一候補: 数独ヘルパー)。他のアプリと重複すると使えない。手順4で分かる。

## 1. Apple Developer Program に登録する(いちばん時間がかかる)
- ☐ https://developer.apple.com/programs/enroll/ から登録する。年額 12,980円。
- ☐ Apple ID(2ファクタ認証つき)が必要。個人か組織かを選ぶ。個人がいちばん簡単。
- ☐ 本人確認がある。承認まで数時間〜数日かかることがある。
- 承認されるまでは、以降の手順(特に3〜6)を進められない。

## 2. プライバシーポリシーを公開する(URL が必須)
- ☐ `docs/privacy-policy.md` の内容を確認する(提供者名は taiki、問い合わせ先は GitHub の Issues にしてある)。変えたい場合は日本語・英語の両方を書き換える。
- ☐ GitHub の Settings → General → Features で **Issues がオン**になっていることを確認する(問い合わせ先のリンクが使えなくなるため)。
- ☐ GitHub に push する。
- ☐ GitHub の `daichaco/sudokuapp` → Settings → Pages → Source を「Deploy from a branch」、Branch を `main`、フォルダを `/docs` にして保存する。
- ☐ 公開された URL を控える(たとえば `https://daichaco.github.io/sudokuapp/privacy-policy`)。開いて表示できるか確認する。
- 注意: リポジトリが非公開(private)だと、無料プランでは Pages を使えない。その場合は別の方法(自分のサイト、Notion の公開ページなど)で公開する。

## 3. Xcode の署名を設定する(登録の承認後)
- ☐ Xcode で `SudokuHelper.xcodeproj` を開き、Signing & Capabilities で Team を、登録した(有料の)チームにする。
- ☐ Bundle Identifier が `com.taiki.SudokuHelper` になっていることを確認する。
- 注意: 今の `project.pbxproj` には、以前の無料チームの ID が入っている。有料チームに変えると書き換わる。

## 4. App Store Connect でアプリを作る
https://appstoreconnect.apple.com → マイApp → 「+」→ 新規App
- ☐ プラットフォーム: iOS
- ☐ 名前: 数独ヘルパー(重複していたら `AppStore/listing-ja.md` の候補を使う)
- ☐ プライマリ言語: 日本語
- ☐ バンドルID: `com.taiki.SudokuHelper`(一覧に出るのは、手順3の後)
- ☐ SKU: 自由な英数字(例: `sudokuhelper-001`)。あとで変えられない。

## 5. アプリの情報を入力する(`AppStore/listing-ja.md` をコピーして貼る)
- ☐ 価格と配信: 無料(または有料)、配信地域
- ☐ App のプライバシー: 「データを収集しない」を選ぶ。プライバシーポリシーの URL を入れる
- ☐ 年齢制限の質問票: すべて「なし」(結果は 4+)
- ☐ カテゴリ: ゲーム > パズル(セカンダリは任意)
- ☐ バージョン 1.0 のページ: スクリーンショット(4枚、`AppStore/screenshots/`)、プロモーションテキスト、説明文、キーワード、サポート URL、著作権
- ☐ App Review 情報: 連絡先(氏名・電話・メール)と、審査メモ(`listing-ja.md` にある文面)。サインインは不要
- ☐ 輸出コンプライアンス: 質問が出たら「独自の暗号化は使っていない」

## 6. ビルドをアップロードする
- ☐ 実行先を「Any iOS Device (arm64)」にして、Product → Archive を実行する。
- ☐ Organizer が開いたら、Distribute App → App Store Connect → Upload を選ぶ。
- ☐ 数分〜30分ほど待つと、App Store Connect にビルドが表示される(メールが届く)。
- ☐ バージョン 1.0 のページで、そのビルドを選ぶ。
- 2回目以降のアップロードは、ビルド番号(Build)を上げる必要がある。

## 7. 提出の前に、実機で最終確認する(強く推奨)
- ☐ **実際の紙の数独**(新聞・パズル本)を撮影して読み取る(まだ紙では試せていない。読み違いがあれば教えてほしい)
- ☐ 写真ライブラリの写真から読み取る
- ☐ 「ヒント」「戻す」「解答を見る」「盤面一覧」「アプリを閉じて再開」
- ☐ できれば TestFlight で、自分の iPhone に配信して確認する(App Store Connect の TestFlight タブ)

## 8. 審査に提出する
- ☐ バージョンのページで「審査へ提出」を押す。
- ☐ 審査は、たいてい1〜2日。質問や指摘が来たら、App Store Connect のメッセージで答える。
- ☐ 公開のタイミング(承認後すぐ / 手動)を選ぶ。

## 公開後
- ☐ 更新するときは、バージョン(1.1 など)とビルド番号を上げて、手順6→8を繰り返す。
