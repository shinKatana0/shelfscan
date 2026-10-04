<!-- TRANSLATED-FROM: README.md blob bc464a1479f86ece61cb066deea65a4b54fa9366 CURRENT -->

[English](README.md) · [Русский](README.ru.md) · **日本語**

# ShelfScan

[![CI](https://github.com/shinKatana0/shelfscan/actions/workflows/ci.yml/badge.svg)](https://github.com/shinKatana0/shelfscan/actions/workflows/ci.yml)

手元にあるゲームを、一つずつ入力せずにデジタルのコレクションへ。
棚の写真を撮る、PC 内のゲームを調べる、GOG Galaxy のライブラリを読む。
ShelfScan は結果をまとめて確認できるようにし、Tonkatsu Box 用の
ファイルや CSV に書き出します。

ShelfScan が担当するのは認識と書き出しです。コレクションの管理は、
使い慣れたアプリに任せられます。

## スキャン → 確認 → 書き出し

**スキャン:** 棚の写真、または PC 上の対応する入力元を選びます。
**確認:** タイトルや機種を直し、読み取れなかったものを追加します。
**書き出し:** 確認した項目を Tonkatsu Box 用の Custom Cards JSON、
従来の `.xcoll`、または CSV に保存します。

## 読み取れるもの

- ゲームの棚やパッケージの写真。JPEG、PNG、WebP に対応し、Windows
  では HEIC も扱えます。
- PC のフォルダーにあるインストール済みゲーム。利用できる場合は
  GOG のインストール情報も読みます。
- Windows 上の GOG Galaxy ライブラリ。未インストールのゲームも対象です。
- アプリで選んだメディアフォルダー。対応するファイル名から映画や
  アニメーションの項目も得られます。種類は確認画面で修正でき、
  アニメにも変更できます。

複数の入力元を一度にスキャンできます。重複は確認前にまとめますが、
読み取ったタイトルや機種が常に正しいとは限りません。入力形式や制限は
[ガイド](doc/guide.md)（英語）にまとめています。

## ダウンロードして使う

[最新の GitHub リリース](https://github.com/shinKatana0/shelfscan/releases/latest)
から、**Windows x64** 向けのポータブル版 `ShelfScan-win-x64.zip` を
入手できます。フォルダーをすべて展開し、その中の
`shelfscan_app.exe` を起動してください。インストーラーや
Dart／Flutter の開発環境は不要です。

写真を読み取るには、設定で画像認識のプロバイダーを選びます。
Windows ではローカルの Ollama が初期設定です。Ollama は別途
インストールし、`ollama pull qwen3-vl:8b-instruct` でモデルを
取得してください。標準の接続先は `http://localhost:11434` です。
その後、写真や入力元を選び、結果を確認して書き出します。

Android アプリのコードはありますが、公開されている Android
向けビルドはありません。自分でビルドする場合は
[Android のビルド手順](doc/android-build.md)を参照してください。
CLI と詳しい初回手順は[ガイド](doc/guide.md)（英語）にあります。

## 写真と API キー

ShelfScan 専用のアカウントやサーバーは不要で、コレクションを
保存する独自のデータベースもありません。API キーは同梱していません。
Windows PC 上で動く Ollama ならキーなしで使えます。ただし、
LAN 上の別の Ollama サーバーを指定すれば写真はそこへ送られます。
Anthropic または OpenAI 互換のサービスを選ぶと、そのサービスへ
写真を送ります。カタログ検索では、自分で用意した認証情報を使い、
タイトルを IGDB や TMDB に送ることがあります。Windows で
クラウドサービスが自動的に選ばれることはありません。

設定方法とデータの送信先は
[プロバイダーの説明](doc/guide.md#step-2--choose-a-vision-backend)
と[写真の送信先](SECURITY.md#your-photographs)を確認してください
（いずれも英語）。

## Tonkatsu Box との連携

ShelfScan は項目を認識し、確認するところまでを担当します。
Tonkatsu Box はカタログとの照合、表紙、メタデータを扱います。
標準の書き出しは Tonkatsu Box v0.45 対応の Custom Cards JSON
です。取り込み時にソース検索を有効にすると、一意に見つかった項目は
カタログに紐づくカードになり、候補が複数ある項目や見つからない項目は
カスタムカードのまま残ります。ShelfScan が無理に候補を選ぶことは
ありません。従来の `.xcoll` 形式も使えます。

詳しい形式と取り込み方法は
[Tonkatsu 連携ノート](doc/integrations/tonkatsu-handoff.md)
（英語）を参照してください。

## 書き出す前に

写真の文字やファイル名は読み間違えることがあります。機種を推測して
誤るより、空欄のまま確認に回すほうが安全です。次の観察は検証した
ローカルモデルについてのもので、すべてのモデルに当てはまる話では
ありません。

<!-- measured-on: qwen2.5vl:7b -->

`qwen2.5vl:7b` は、パッケージに印刷された機種表示を見落とすことがありました。

<!-- /measured-on -->

<!-- measured-on: qwen2.5vl:7b -->

縮小した写真では、`qwen2.5vl:7b` は背表紙の細かな文字を読み取りにくくなりました。

<!-- /measured-on -->

<!-- measured-on: qwen2.5vl:7b -->

架空の密集した棚の画像では、`qwen2.5vl:7b` が背表紙を報告せずに
読み飛ばすことがありました。

<!-- /measured-on -->

<!-- measured-on: qwen2.5vl:7b -->

ローカルでの比較では、`qwen2.5vl:7b` に二度目の読み取りを加えると、
誤った項目や重複も増えました。追加分も必ず確認してください。

<!-- /measured-on -->

写真の撮り方と確認の進め方は
[ガイド](doc/guide.md#step-1--photograph-the-shelf)（英語）にあります。

### 表計算ソフトで CSV を開く場合

CSV は取り込み用の形式です。Excel、LibreOffice、Google Sheets
では、`=`、`+`、`-`、`@` で始まるセルを数式として扱うことが
あります。ShelfScan は他のアプリへ元の名前を渡すため、文字列を
書き換えません。表計算ソフトで確認する場合はダブルクリックで
開かず、列を文字列として**インポート**してください。Excel では
*Data → From Text/CSV*、LibreOffice では Text Import で
*Evaluate formulas* をオフにします。

## ドキュメント

- [ユーザーガイド](doc/guide.md) — 初回のスキャン、確認、書き出し、
  問題への対処（英語。[旧訳](doc/guide.ja.md)もあります）。
- [プロバイダー](doc/guide.md#step-2--choose-a-vision-backend)と
  [プライバシー](SECURITY.md#your-photographs) —
  モデル、キー、データの送信先（英語）。
- [Tonkatsu Box 連携](doc/integrations/tonkatsu-handoff.md) —
  現行の形式と互換性（英語）。
- [設計](ARCHITECTURE.md)と[ビルド手順](doc/build.md) —
  開発者向け（英語）。

開発に参加する場合は [CONTRIBUTING.md](CONTRIBUTING.md) を
お読みください。

## ライセンスと帰属表示

ShelfScan は [MIT ライセンス](LICENSE)で公開しています。
本プロジェクトは Tonkatsu Box、CLZ、GAMEYE と提携しておらず、
これらから承認も受けていません。製品名や商標はそれぞれの
権利者に帰属します。ゲームのメタデータは IGDB が提供します。

TMDB が指定する文言を英語のまま掲載します。

This application uses TMDB and the TMDB APIs but is not endorsed, certified,
or otherwise approved by TMDB.

TMDB への接続には、利用者が用意したトークンだけを使います。

<img src="app/assets/tmdb/blue_long_1.svg" alt="TMDB" width="180">

TMDB のロゴは帰属表示のために無改変で同梱しています。プロジェクトの
MIT ライセンスの対象外です。詳しくは [NOTICE](NOTICE) を参照してください。
