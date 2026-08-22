[English](guide.md) · [Русский](guide.ru.md) · **日本語**

> **`doc/guide.md` の翻訳。** Translated from `85cbd54` (2026-08-22).
> 英語の原文が先に進んでいないかは、次の一行で確認できます:
> `git log --oneline 85cbd54..HEAD -- doc/guide.md` — 出力が空なら、この翻訳は
> 最新です。規則の全文は一箇所にのみ置いてあります:
> [`../README.md` の「Translations」](../README.md#translations)。
> **コードブロックとプログラムの出力は翻訳していません。** それらはツール自身が
> 印字する文字列です。このページが参照する資料（`measurements.md`、
> `decisions/`、`../ARCHITECTURE.md`）は英語のみです。
>
> **この日本語訳は機械翻訳ではありませんが、母語話者の校閲を受けていません。**
> 数値と主張は英語原文と突き合わせて確認済みですが、語感の保証はありません。
> 誤りを見つけたら課題として登録してください。
>
> 文体について: この手引きは読者に手順を説明する文書なので「です・ます」で
> 書いています（`README.ja.md` は仕様書なので「である」調です）。ただし
> 制約と警告はぼかしていません。読めないものは「読めません」と書いてあります。

# shelfscan — 一回の実行を通しで

このページは、一回の実行を、何もない状態から Tonkatsu Box に取り込まれた
コレクションまで、実際にやる順番どおりにたどります。判断はそれが出てくる場所で
説明し、冒頭にまとめて並べることはしません。各手順には、何がうまくいかないか、
そのときプログラムが何を言うかを書いてあります。その文言こそが製品であり、
どれか一つに見覚えがあれば、たいていそれで解決します。

最後に手に入るもの: Tonkatsu Box が取り込む `.xcoll` ファイル、または任意の表計算
ソフトが読む `.csv`。shelfscan はカタログもデータベースも持ちません。あなたの棚を
認識し、その結果をそれらを持つアプリに渡します。

進み方は二つあり、この手引きの最初の一歩は、実のところその選択です。

- **鍵なし。** ローカルのビジョンモデルと CSV の書き出し。どこにも登録せず、
  支払いも鍵もありません。Windows での既定はこれです。
- **フル。** 同じスキャンに IGDB の鍵を足したもので、`.xcoll` を可能にするのが
  この鍵です。あの形式は IGDB の ID しか運ばないので、ID のない項目はそもそも
  ファイルに入れません。

鍵なしで始めて後から鍵を足すこともできます。鍵が効くのは一つの段階だけで、その
段階は、すでに費用を払って済ませたスキャンの上で単独で再実行できます。

---

## 始める前に

検証済みのホストは **Windows** です。パイプライン自体は素の Dart でプラット
フォームに依存しませんが、この手引きの中で二つだけ依存するものがあり、どちらも
出てくる場所で明示します（HEIC の変換と、GOG Galaxy ライブラリ）。

Dart SDK が要ります。そのうえで、一度だけ:

    cd packages/shelfscan_core
    dart pub get

**以下のコマンドはすべて `packages/shelfscan_core` から実行します。** このツール
はリポジトリのルートから実行されることもよくあり、だからこそ、渡されたパスを
入力どおりではなく*絶対パスに正規化して*返します。`../../photos` のような相対
パスは、その二つのディレクトリのうち一方からは正しく、もう一方からは誤りです。
エラーメッセージの中の見慣れない絶対パスが、そのまま答えになります。

コマンドの一覧はいつでも、引数なしで実行すれば見られます:

    dart run shelfscan_core:shelfscan

その使用法テキストが正典です。このページとその出力が食い違ったら、正しいのは
出力のほうです。

---

## 手順 1 — 棚を撮影する

**解像度が梃子です。** あなたが動かせるもののうちこれが最大で、しかも実在の
棚で計測されています。同じ棚が 4000×3000 では、同じ写真二枚の 1200×900 に対して
**二倍以上**の検出になります。同じモデル、同じプロンプト、ほかは何も
変えていません。このプロジェクトが品質をより大きなモデルで買おうとした試みは
ことごとく失敗し、画素で買おうとした試みはことごとく成功しました。

その二つの数値が、このプロジェクト標準の対照セット `CONTROL-LOWRES` と
`CONTROL-HIRES` です。同じ棚を、この二つの解像度で二度撮ったものです。私的な
写真なので公開されていません。読めるのはそれらが出す数値のほうで、
[`measurements.md`](measurements.md)（英語）は、このプロジェクトのあらゆる数値を
そのどちらかに対して示しています。

実際的には、スマートフォンのカメラの最大解像度で撮り、PC に移す途中でメッセージ
アプリに縮小させないでください。フレームを背表紙で埋めてください。フレームが
切っている列も読まれますし、そこから出る断片は捏造ではなく正直な部分読みですが、
断片は断片なので、列全体を入れたほうが安く済みます。

**読める形式。** JPEG、PNG、WebP です。各ファイルは**名前ではなく中身で**識別
されるので、スマートフォンやメッセージアプリが `.jpg` に改名した HEIC も HEIC と
して認識されて変換され、壊れた JPEG として送信されることはありません。

**HEIC** — スマートフォンのカメラの既定 — は **Windows では**受け付けます。各
ファイルはスキャン前に一時ディレクトリで JPEG に変換され、元のファイルの隣には
何も書かれません。それ以外の環境、および Windows の HEIF 拡張がない場合や変換に
失敗した場合は、そのファイルは理由とともに stderr に名前が出て飛ばされます。黙って
捨てられることはありません。自分で `.jpg` に変換して再実行してください。

写真は専用のディレクトリに入れてください。`scan` が取るのはディレクトリであって
ファイルではありません。

### うまくいかないとき

**ディレクトリの中に写真でないファイルがある。** ファイルごとに一行、そのあとに
まとめの一行が出ます。まとめに数字を畳み込まないのは、古い JPEG 二枚の隣に新しい
HEIC 三枚を置いた実行が、本物の実行と見分けのつかない結果を出していたからです:

    SKIPPED: notes.txt (.txt) -- <reason>
    !! 1 of 4 file(s) in this directory will NOT be scanned. Accepted: .jpg, .jpeg, .png, .webp, and .heic, .heif, .hif (converted to JPEG first)

受け付ける一覧は今いるホストに合わせて組まれるので、HEIC を変換できないマシンが
変換できると称することはありません。

**ディレクトリに読めるものが一つもない。** これは「0 枚」の成功ではなく、エラー
終了です:

    No readable photo in D:\photos: all 3 file(s) were skipped. Found: .heic x3. Accepted: .jpg, .jpeg, .png, .webp

ディレクトリが単に空のときは `No files to scan in D:\photos` です。

**パスが違う。**

    No photo directory at D:\photso
    Not a photo directory: D:\photos\shelf1.jpg is a file -- scan takes the directory that holds your photos, not one photo

**HEIC が変換された。** 失敗ではありませんが、表示されます。遅い一枚が平均の中に
隠れないよう、ファイルごとに出ます:

    CONVERTED: shelf-1.heic -> jpeg in 812 ms
    HEIC: 3 file(s) converted to a temp directory in 3412 ms total (process start included). Nothing was written next to the originals.

---

## 手順 2 — 画像認識のバックエンドを選ぶ

三つあり、選択は費用と、何が正しく読まれるかの間の選択です。

    --provider ollama      local, needs a running Ollama server (DEFAULT)
    --provider anthropic   cloud, needs ANTHROPIC_API_KEY
    --provider openai      any endpoint speaking the OpenAI /chat/completions
                           API (Groq, OpenRouter, Mistral, GitHub Models,
                           Cerebras, Gemini's compatibility endpoint)

**デスクトップの既定はローカルで、クラウドのエンドポイントはどれも明示的に選ぶ
ものです。** あなたの写真は、あなたが指定したエンドポイントへ丸ごと送信されます
し、無料プランは送られたもので学習することで賄われていることが多いからです。
これはあなたの家の写真です。そこへ向ける前に、そのサービスのデータの扱いを読んで
ください。

**「ローカル」は「オフライン」を意味しません。** ローカル実行はすべての写真を
`SHELFSCAN_OLLAMA_URL` へ POST しますが、それを決めるのはあなたです。既定の
`http://localhost:11434` を指していればマシンからは何も出ませんが、LAN 上の別の
マシンを指していれば、写真は平文の HTTP でそこへ送られます。鍵なしであることと
オフラインであることは、別の主張です。

### それぞれが実際に何を読むか

同じ五枚の対照写真で計測し、別の JSON ファイルとではなく写真そのものと目で
突き合わせています。数値と注意事項の全文は
[`measurements.md`](measurements.md) の「The second lever works」および
「A bigger local model, measured and rejected」にあります（英語）。

| | ローカル `qwen2.5vl:7b` | `gpt-4.1-mini` | `gpt-5.5` |
|---|---|---|---|
| 高解像度での検出数 | 基準 | 少ない | やや多く、写真ごとにぶれる |
| 日本語の背表紙 | すべて書き起こす | **一本も読まない** | すべて書き起こす |
| 印刷された Switch 2 の帯 | **読まない** — それらのケースに `PS2` のヒントを付ける | 読まない | 背表紙ごとに読む。最大解像度の写真三枚、各五回ずつでヒントはすべて正しい。1200×900 では別途測定し、帯を確認した写真一枚でどのケースも正しい |
| 1200×900 での捏造タイトル | なし | 五回中三回、一件 | 五回とも、なし |
| 費用 | **$0** | 有料 | 写真三枚の棚で約 **$0.45** |

この表から持ち帰るべき点が二つあります。どちらも逆に思い込みやすいものです。

- **日本語で失敗するのはローカルモデルのほうではありません。** ローカルモデルは
  日本語の背表紙をすべて書き起こし、`gpt-4.1-mini` は一本も読みません。
  「クラウドモデルなら日本語の背表紙を読む」は計測済みで、このモデルについては
  偽です。
- **ローカルモデルが実際に取りこぼすのは、印刷された Switch 2 の帯です。** その
  背表紙は `PS2` のヒントを付けて返り、それは誤りです。これに対してプロンプトの
  文言を十三通り試し、どれも効きませんでした。つまり調整で済む話ではなくモデルの
  限界です。`gpt-5.5` は帯を背表紙ごとに読んで当てますが、それでも 4000×3000 で
  五回中二回、一行を捏造します。つまりそちらでも人間の確認は省略できません。

Switch 2 のケースが数本あって、棚を一度スキャンするだけなら、クラウドでの一回は
コーヒー一杯ほどの価値があります。繰り返しスキャンする場合や、棚に Switch 2 の帯
がない場合は、ローカルは費用ゼロで、失うものもわずかです。

### ローカルモデルの準備

Ollama を入れ、ビジョンモデルを取得し、サーバを起動したままにします。組み込みの
既定は `qwen2.5vl:7b` と `http://localhost:11434` で、どちらも
`SHELFSCAN_OLLAMA_MODEL` と `SHELFSCAN_OLLAMA_URL` で上書きできます。モデルが
収まるマシンで、4000×3000 の写真一枚あたり **約 25 秒**を見込んでください。

### クラウドのバックエンドの準備

PowerShell:

    $env:ANTHROPIC_API_KEY = '...'

または、OpenAI 互換のエンドポイントなら、次の三つすべて:

    $env:SHELFSCAN_OPENAI_BASE_URL = 'https://api.groq.com/openai/v1'
    $env:SHELFSCAN_OPENAI_MODEL = '...'
    $env:SHELFSCAN_OPENAI_API_KEY = '...'

ベース URL はバージョンの区切りまで含めます。これらを設定してもエンドポイントの
設定が済むだけで、選択はされません。選ぶのは `--provider` フラグだけです。

`SHELFSCAN_ANTHROPIC_MODEL` は任意です。未設定なら組み込みの既定を使うので、
始めるのにモデル ID を知っている必要はありません。モデル ID は提供元が公表する
ものです。

変数は、コマンドを実行するシェルの環境から読まれます。**このコードベースには
`.env` ファイルを解釈するものはありません。**
[`.env.example`](../.env.example) は名前の参照一覧にすぎず、`.env` にコピーしても
効果はなく、エラーも出ません。設定されているが空の変数は、どこでも未設定として
扱われます。これは意図的です。

### うまくいかないとき

**Ollama が動いていない:**

    Cannot reach Ollama at http://localhost:11434 -- nothing answered there. Start the server with: ollama serve. If that address is another machine, check it is right and reachable from here. (<socket reason>)

**モデルを取得していない:**

    Ollama at http://localhost:11434 has no model "qwen2.5vl:7b" (HTTP 404) -- it is not <...>

**Ollama は動いているが応答しない。** 別の故障で対処も別なので、メッセージも別に
してあります。末尾が診断です。詰まったモデルランナーはちょうどこう止まりますし、
`qwen2.5vl:7b` はここでは 4000×3000 の写真に約 25 秒で答えるので、モデルが単に
遅いと決めつける前に `ollama ps` でサーバが生きているか確認してください。マシンに
対して大きすぎるモデルは、ここで計測された中で唯一、正当に数分かかる場合です。

それに当てはまるなら、呼び出しごとの上限を上げてください:
`SHELFSCAN_VISION_TIMEOUT=<秒>`。これは、使用中のプロバイダにかかわらず、写真
一枚あたりの画像認識**一回**の呼び出しを制限します。未設定なら 120 秒です。
受け付ける範囲は 1 から 1800 で、それ以外は既定値に黙って置き換えられるのでは
なく拒否されます。効かなかった引き上げは、直そうとした当のタイムアウトと見分けが
つかないからです。

**クラウドの鍵がない。** 何も読まれず、写真が一枚も動く前に実行が終了します:

    Provider "anthropic" needs ANTHROPIC_API_KEY. <...>
    The "openai" provider needs SHELFSCAN_OPENAI_MODEL. <...>

**呼び出しがすべて拒否された。** モデル ID が違うか、鍵が違います。実行は集約
メッセージとともに終了コード 2 で終わります。「スキャンするものがない」ときの
終了とは区別されています。こちらはスキャンが実行され、そのうえで全部の呼び出しが
弾かれたことを意味するからです。

### `--fallback` について

`--fallback` は、**すべての**写真を読み直す**二つ目の**ビジョンモデルを指定し、
二つの読みを統合します。頼まない限り無効ですし、どの写真に必要かを自分で判断する
こともしません。ローカルモデルは読めなかった背表紙を報告できないので、判断の材料が
そもそもないからです。実行の画像認識の費用は倍になり、クラウドの fallback を使え
ば写真はすべて二度目の送信をされます。実行はそれを言葉ではなく数で言います:

    Fallback: cloud (<model>, <sampling>) -- re-reads ALL 3 photo(s), 3 extra call(s).

---

## 手順 3 — IGDB の鍵を取得する

ここが最も行き詰まりやすい手順なので、まるごと書いてあります。必要なのは
`.xcoll` のためだけで、CSV は鍵なしで動きます。

**何のためのものか。** パイプラインの第 3 段階は、背表紙から読んだ各タイトルを
IGDB の正規のゲーム ID とプラットフォーム ID に解決します。Tonkatsu の `.xcoll`
light 形式は、項目ごとに*まさにその二つの ID* だけを運び、ほかは何も運びません。
カバー画像とメタデータは Tonkatsu Box が取り込み時に自分で取得します。したがって
IGDB と突き合わない項目は、`.xcoll` に書き込むものがそもそもありません。CSV には
タイトルの列があるので、問題なく運べます。

**shelfscan は資格情報を同梱せず、プロキシも運用しません。** 配布されるクライア
ントに埋め込まれた秘密は秘密ではありませんし、Twitch の規約は client secret の
共有を禁じていますし、共有プロキシを置けばこのプロジェクトが他人の家の写真の
処理者になってしまいます。だから鍵はあなたのもので、あなたのものであり続け、
費用はかかりません。

### アプリケーションの登録

IGDB の資格情報は Twitch アプリケーションの資格情報です。IGDB 単独の登録は
ありません。

1. Twitch にサインインするか、アカウントを作ります。
2. そのアカウントで**二要素認証を有効にします**。有効でないと Twitch は
   アプリケーションを登録させません。ここで止まる人が最も多いのですが、これは
   Twitch の要件であって shelfscan の要件ではありません。
3. `https://dev.twitch.tv/console/apps` へ行き、**Register Your Application** を
   選びます。
4. 記入します:
   - **Name** — Twitch 内で一意なら何でも。`shelfscan-<あなたの名前>` で十分です。
   - **OAuth Redirect URLs** — `http://localhost`。必須項目です。shelfscan は
     これを一切使いません。client id と secret による machine-to-machine の認証な
     ので、ブラウザのリダイレクトは起きません。
   - **Category** — *Application Integration*。
5. **Create**、続いて作ったアプリケーションの **Manage**。
6. **Client ID** をコピーします。
7. **New Secret** を押して secret をコピーします。**一度しか表示されず、後から
   読み直すことはできません。** なくしたら別のものを生成してください。古いものは
   使えなくなります。

両方とも**一つの**アプリケーションから取ります。片方の id ともう片方の secret を
混ぜるのは実際によくある間違いで、しかもトークンの取得時ではなく検索の時点という
遅い段階で失敗します。

### ツールに渡す

PowerShell:

    $env:IGDB_CLIENT_ID = '...'
    $env:IGDB_CLIENT_SECRET = '...'

bash:

    export IGDB_CLIENT_ID=...
    export IGDB_CLIENT_SECRET=...

スキャンを実行するのと同じシェルで設定してください。両方が設定されていて、かつ
空でない必要があります。どちらか一方が欠けていれば、解決の段階そのものがありま
せん。

Flutter アプリでは、代わりに**設定**の IGDB の二つの欄に入れます。ファイルでは
なく OS のキーチェーンに保存されます。

### うまくいかないとき

**どちらも設定されていない。** `scan` は失敗しません。機能を落としたうえで、
そう言います:

    IGDB credentials not set -- resolve stage will be skipped, games stay unresolved (fine for vision validation).

`resolve` のほうは失敗します。解決こそがその全目的だからです:

    The "resolve" command needs IGDB credentials: set IGDB_CLIENT_ID and IGDB_CLIENT_SECRET (see .env.example). Resolving is the entire point of this command, so there is nothing useful to do without them.

**client id が違う。** Twitch は知らない client id に対して 401 ではなく 400 を
返します。これは対の片方を指し示せる唯一のステータスなので、メッセージもそう
指します:

> refused the credentials (HTTP 400) before it issued a token. That is the
> client id it does not recognise rather than the secret: check
> IGDB_CLIENT_ID against the application at
> `https://dev.twitch.tv/console/apps`.

**対として機能しない。** Twitch からの HTTP 401 または 403 です。id と secret が、
Twitch の知っているアプリケーションに対する有効な組になっていません。両方は一つの
アプリケーションから来るもので、secret は一度しか表示されず読み直せません。確信が
なければ再生成してください。

**別々のアプリケーションのもの。** Twitch が直前に発行したトークンに対する、IGDB
からの HTTP 401 または 403 です。検索は id とトークンを別々に送るので、その二つが
食い違っていることは IGDB にしか見えません。

**ネットワークがない。** メッセージは、失敗したのは client id でも secret でも
ないこと、アドレスはあなたが入力したものではなくビルドに固定されていること、
設定側に直すものは何もないことをはっきり述べます。マシンがオンラインかどうか、
プロキシやファイアウォールが接続を拒んでいないかを確認してください。

**このどの場合でも、失われるものはありません。** この段階は正規の ID を足すだけ
です。行は未解決のままレビューに入っており、そこで手作業で突き合わせられます。
IGDB の失敗から復旧するのに再スキャンは不要です。資格情報を直して、すでにある
ファイルに対して `resolve` を実行してください。

---

## 手順 4 — スキャンを実行する

    dart run shelfscan_core:shelfscan scan D:\photos -o collection.review.json

`-o` の既定はカレントディレクトリの `collection.review.json` です。`scan` が取る
オプションは、次のものだけです:

    -o <file>            where to write the review document
    --provider <name>    anthropic | ollama | openai
    --fallback <name>    anthropic | ollama | openai | none
    --aliases <file>     regional title table (data/title_aliases.json)
    --installs <dir>     add a folder of installed games to this run
    --library            add the GOG Galaxy library to this run
    --galaxy-db <path>   where that database is, if not where it is expected

最後の三つは下の第 2 部のものです。ここに挙げているのは、入力源を混ぜる実行は
**一回**の実行でなければならず、それをやるコマンドがこれだからです。

### 表示されるもの

選ばれたプロバイダ。後から実行を取り違えて帰属させられないようにするためです:

    Vision: local Ollama (qwen2.5vl:7b)

続いて各段階が、段階ごとに一行、項目ごとに一行で出ます。警告は stderr に出ます:

    == VISION ==
      VISION 1/3
    ...
    WARN: <...>

そして要約です。範囲の行は、カバーしたものだけでなくカバー**しなかった**ものも
述べます。ディレクトリにファイルが五つあったとき、「Scanned 2 photo(s)」は真で
ありながら誤解を招くからです。
*これは説明用の出力です。ブロック内のファイル名と数値は作り物であり、実際の棚
を測ったものではありません。*

    Scanned 3 photo(s): 45 game(s) detected, 4 unresolved.

続いて、該当するときは:

    Unread-spine reports: 2 -- one report can describe several spines, so this is not a count of spines.
      by photo: shelf-3.jpg: 1 report(s), ...
      by script: japanese: 1, ...
      shelf-3.jpg: <the model's own wording>

この書き方は意図的です。モデルが見たうえで読めなかった背表紙は、意図的に `games`
に入れません。そのために何も捏造しないためです。だからこの行がなければ、読めない
日本語の背表紙が並ぶ写真は、空の棚と同じに見えてしまいます。そして単位は本当に
*報告*であって背表紙ではありません。一件の報告が二、三本を同時に指した例が計測
されています。

    Platform hints refused: 4 (kept per row in "discarded_platform_hint")
      4 x "PS2" -- <why it was refused>

拒否されたヒントは捨てられるのではなく名指しされます。プラットフォームを黙って
失った行は、ブランド表示が判読できなかった背表紙とまったく同じに見えるからです。

最後に:

    Review file: collection.review.json -- set "status" per game, then export.

### うまくいかないとき

**別のコマンドのフラグを渡した。** 何かを読む前に検査されるので、費用は発生
しません:

    Unknown option "--targt" for "export". Nothing was read. Options of "export": -o, --target.
    "--target" is not an option of "scan" -- it belongs to "export". Nothing was read. Options of "scan": -o, --provider, --fallback, --aliases, --installs, --library, --galaxy-db. Run "shelfscan" with no arguments for what each command reads.

**`-o` の打ち間違い。** これも画像認識の実行の前に答えます。書き込みは、すでに
数分を費やした実行の最後の一文だからです:

    Not an output file: D:\out is a directory -- -o names the file to write, not the directory to write it into
    No output directory at D:\repots -- -o writes D:\repots\shelf.csv, and nothing here creates a directory for you
    Cannot write to D:\shelf.csv -- <the OS message>

存在しない親ディレクトリは作られずに拒否されます。`-o repots/x.csv` はそうしないと
黙って成功し、打ち間違いをディスク上に永久に残すからです。

**実行に時間がかかり、棚にある数より少ない行しか出なかった。** それは失敗では
なく、確認の手順が存在する理由そのものです。手順 5 へ進んでください。

---

## 手順 5 — レビューを読む

モデルの確信度は信用できないので、**すべての項目が書き出し前に人間の確認を
通ります**。これは後から付け足された形式ではなく、ツール全体がその周りに組まれて
いる境界です。その手前はすべて認識、その先はすべて整形です。

文書は一つで、読み方が二つあります。`collection.review.json` は設計として手で編集
でき、Flutter アプリはその同じ文書を承認／却下の画面として描きます。どちらも同じ
書き出しに繋がるので、どちらを使っても構いません。

### 行が取りうる四つの状態

ファイルの中では、`games` の各項目が `status` を持ちます:

| status | 意味 | 書き出される? |
|---|---|---|
| `pending` | まだ決めていない | いいえ |
| `approved` | 突き合わせたまま採用 | はい |
| `rejected` | 誤検出、または所有していない行 | いいえ |
| `edited` | 突き合わせを手で置き換えた | はい |

`edited` は `approved` とまったく同じに書き出されます。アプリのカウンタは両方を
数えるので、`approved` という語を数えるのではなく「Export 41 items」と表示します。

### アプリの表示の意味

各行は、突き合わせられたタイトルを表示します。何も突き合わなかったときは、背表紙
から読んだ生のテキストを表示します。その下の副題は、行を見比べやすいように、常に
同じ順序で並びます:

- **プラットフォーム** — 突き合わせられていれば正規のプラットフォーム名、
  なければケースから読んだヒント、それもなければ `?`;
- **`raw: "..."`** — 背表紙から実際に読み取ったもの。入力した項目なら
  **`added by hand`**;
- **発売年** — IGDB が返したとき;
- **`matched as "..."`** — 突き合わせに使われた別名。日本語の生テキストの上に
  英語の正規タイトルが載るのはこれによります;
- **`matched by store id`** または **`score 87%`** — どう突き合わせたか。ストア
  ID による結合はパーセントを書きません。その行のパーセントは、誰も取っていない
  文字列一致の測定値になってしまうからです;
- **`not in .xcoll -- tap to pick a match`** — 下記参照。鍵なしの実行では出ません。
  そこではすべての行に当てはまってしまい、そもそもタップして開く候補の
  一覧がありません;
- **状態の語** — 決めた後に;
- **`hint refused: "..."`** — パイプラインが捨てたプラットフォームのヒント。
  ブランド表示が判読できなかった行と取り違えられないよう、名指しされます;
- **`note: "..."`** — あれば。

左の**鉛筆のアイコン**は、写真から読んだものではなくあなたが入力した項目を示し
ます。自分の入力を写真と照合し直して時間を使わずに済むようにするためです。

右の**チェック**と**バツ**のボタンで承認と却下をします。色だけが手がかりになる
ことはありません。副題が状態を語でも綴ります。

**任意の行をタップ**すると候補一覧が開きます。解決器自身の選択には印が付きます
が、特別扱いはされません。そのシートの存在意義は、その選択が誤りうることそのもの
です。最後の項目は **No match** で、突き合わせを消して項目を却下します。

### 一覧の上のバナー

- **`N of M photos could not be scanned`** — エラー色で、ファイル名を挙げます。
  そこからのものは一覧に一つも入っていません。
- **`N of M photos were not looked at`** — そこに至る前にスキャンを止めた場合
  です。別のバナーで、意図的にエラー色にしていません。自分で押した停止を失敗だと
  告げられるのは、何も告げられないより悪いからです。
- **`At least N spines could not be read`** — 一件の報告が複数の背表紙を指しうる
  ので実際はもっと多いかもしれない、という但し書きと、それらについては何も捏造して
  いないという約束が付きます。写真ごとに **Add** ボタンがあり、入力した項目をその
  写真のグループに入れます。
- **`Keyless run -- nothing was looked up`** — この実行には IGDB の段階が
  なかったので、どの行も読み取られたままのタイトルです。意図的にエラー色に
  していません。あなたが選んだモードであり、その行を運べる書き出し先を
  バナー自体が名指します。

### `.xcoll` に入れないもの、そしてその理由

`.xcoll` の項目とは、IGDB のゲーム ID とプラットフォーム ID の対**そのもの**です。
代わりに入れられるタイトルの欄はありません。だから IGDB と突き合っていない行は
書き込むものがなく、承認したかどうかとは関係なく、その行自身の上でそう述べます:

    not in .xcoll -- tap to pick a match

そこに入る行は三種類です。IGDB に候補がまったくないタイトル、候補がすべて自動
一致のしきい値に届かず、あなたも選ばなかったタイトル、そして解決器が使えない間に
手で入力した項目です。

**CSV はそのすべてを運びます。** タイトルが空でない限りは、です。それが逃げ道で
あり、鍵なしでの利用が機能を削られた道ではなく本物の道である理由です。

**鍵なしの実行ではどの行もこれに当たる**ので、アプリは行ごとにではなく
一覧の上で一度だけそう述べます。すべてに付いた印は何も指し示せず、
さらに「タップして一致を選べ」という誘いはそこでは事実ですらありません。
何も照会していないので、どの行にも候補がないからです。書き出し先の
シートも、選ぶ前に、印を付けた行を一つも運べない先を告げます。
アプリではこのモードを、**Scan** ボタンの上で名前で選びます。

目安として、開発中に計測した実在の棚では、IGDB の ID が付かない行は少数派でした — どの実行でも出会う程度には現れ、残りを書き出せなくなるほど多くはありません。

そういう行を承認したまま `.xcoll` を書き出そうとすると、アプリはまず止めます。
そして数えるのではなく行を名指しします。数からは行を辿り直せないからです:

> **Unresolved items will be dropped.** 4 approved items have no matched game,
> and the tonkatsu export can only carry matched ones. They will be left
> out: …

**Back to review** と **Export anyway** が付きます。

---

## 手順 6 — 行を手で直す

問題は三種類あり、直し方も三通りです。

### 突き合わせが違う

その行をタップして正しい候補を選びます。状態は `edited` になり、その行は書き出さ
れます。どの候補も正しくなければ **No match** を選びます。突き合わせを消して項目
を却下するもので、それが正直な結末であり、誤った ID をあなたのカタログに入れずに
済みます。

ファイル上では、`"status": "rejected"` にするか、その項目の選択された突き合わせを
直接編集します。

### スキャンが項目をまるごと取りこぼした

読める文字がまったくない背表紙もあります。表がロゴだけで他に何もないケースが
それで、どれだけ頑張ってスキャンしても回収できません。そういう項目に
残された道はタイトルを入力することだけです。

アプリでは、**Add missing item** ボタン、または今見ている写真の未読背表紙バナー
にある **Add** ボタンを使います。後者は新しい行をその写真のグループに入れます。

ファイルでは、`games` にブロックを追記して `resolve` を再実行します。

    {
      "detection": {
        "raw_title": "<the title as you read it off the spine>",
        "platform_hint": "PS4",
        "media_type": "disc",
        "origin": "manual"
      }
    }

必須なのは `raw_title` だけです。`platform_hint` は IGDB の検索を絞るので書く価値
があります。`media_type` は `cartridge`、`disc`、`unknown` のいずれかです。
`origin: "manual"` はその行が人手によるものだと示します。`best`、`candidates`、
`status`、`confidence`、そして写真関連のフィールドはすべて省略できます。入力された
項目はどの写真からも読まれておらず、`resolve` が候補を与えるまで候補を持ちません。

### 鍵がまだなかったので何も突き合わせられていない

手順 3 の IGDB の二つの変数を設定し、すでにあるスキャンに対して解決器を実行します。
**写真は一枚も読まれず、画像認識のプロバイダも作られません**。したがって費用は
かからず、何度でも無料で繰り返せます:

    dart run shelfscan_core:shelfscan resolve collection.review.json

出力の既定は `collection.review.resolved.json` です。入力が上書きされることはない
ので、前後の比較が可能なまま残ります。`-o` で変更できます。
*これは説明用の出力です。ブロック内のファイル名と数値は作り物であり、実際の棚
を測ったものではありません。*

    Resolved 45 detection(s) from collection.review.json:
      auto-matched (score >= 0.85):        41
      candidates below threshold:          14
      no candidates at all:                10
    Output: collection.review.resolved.json (review status reset to pending)

**`resolve` はすべての状態を `pending` に戻します。** これは意図的です。新しい
突き合わせは、古い突き合わせに与えた承認を無効にするからです。だから先に解決し、
後で確認してください。逆順にすると、自分の確認作業を捨てることになります。

### うまくいかないとき

`review.json` は設計として手で編集するものなので、余計な一文字は想定内の入力で
あってクラッシュの理由ではありません。二つの場合を分けてあるのは、直し方が違う
からです:

    Not a review file: D:\collection.review.json is not JSON -- <message> at line 812, column 5 (character 21044). review.json is hand-edited by design, so look at the last edit: an unclosed brace, a trailing comma or an unquoted string.

    Not a review file: D:\collection.review.json is JSON but not a review document -- <the field that is wrong>. Run shelfscan with no arguments for the smallest legal game entry.

行と列を出すのは、実際のスキャンが書く数千行のファイルでは文字オフセットが使い
物にならないからです。パスのエラーはスキャンのそれと対になっています:

    No review file at D:\collection.review.jsn
    Not a review file: D:\photos is a directory -- resolve takes the review.json written by scan, not the directory it sits in

---

## 手順 7 — 書き出す

    dart run shelfscan_core:shelfscan export collection.review.json --target tonkatsu -o shelf.xcoll
    dart run shelfscan_core:shelfscan export collection.review.json --target csv -o shelf.csv

レビューファイル、`--target`、`-o` の三つはすべて必須で、どれか一つでも欠ければ
使用法テキストを印字して終了します。
*これは説明用の出力です。ブロック内のファイル名と数値は作り物であり、実際の棚
を測ったものではありません。*

    Exported 41 of 45 approved game(s) -> shelf.xcoll
      4 left out: the tonkatsu target carries only items with a resolved IGDB match.

この件数は書き出し側に問い合わせたもので、別途導出し直したものではありません。
だから「exported 45」と要約しながらファイルには 41 件、ということは起きません。

**知らない書き出し先を指定すると、存在するものを挙げます:**

    Unknown target "tonkatsu-box". Known: tonkatsu, csv

**CSV を書き出した場合**、これが出ることもあります。該当するときだけで、普通の
書き出しにはそういうセルはありません:

    2 cell(s) begin with =, +, - or @, which Excel, LibreOffice and Google Sheets read as a formula rather than as text:
        title: =SUM(...)
        ...
      They are written through unchanged and an import dialog is unaffected. To read shelf.csv in a spreadsheet, import it with the columns set to Text (Excel: Data -> From Text/CSV) rather than double-clicking it -- README, "Opening the CSV in a spreadsheet".

これらの名前はあなたのもので、そのままの形で書き出されています。セルを書き換える
ものは何もありません。アプリでは同じ情報が、**What to do** ボタンの付いた
スナックバーとして届きます。

---

## 手順 8 — Tonkatsu Box に取り込む

Tonkatsu Box で **Import → Import Collection** を選び、`.xcoll` ファイルを指定
します。

カバー画像とメタデータはそのファイルに入って**いません**し、入れるつもりもあり
ません。shelfscan が書くのは `version: 2` に固定された light 形式のコレクションで、
その項目は IGDB の ID とプラットフォーム ID が一つずつです。それ以外はすべて
Tonkatsu Box が取り込み時に自分で取得します。それがこのツールの前提そのもの——
ID を送り、残りはカタログアプリにやらせる——であり、実在の棚で端から端まで
実行済みです。**承認した項目はすべて取り込まれ、カバー画像とメタデータは取り込み側が取得し、
プラットフォーム ID はすべて正しく**、これには未知のリスクだったコンソール帯
の ID と、ケースから読んだ同一系統内の区別が含まれます。

`.xcoll` 形式は Tonkatsu Box プロジェクトのものであって、このプロジェクトのもの
ではありません。外部との契約として扱い、固定しています。その仕様はあちらの
プロジェクト側にあり、
`packages/shelfscan_core/lib/src/exporters/exporters.dart` の `TonkatsuExporter`
のドキュメントコメントから参照しています。

**バグに見えてバグではないことが一つあります。** 二つのコンソールで所有している
ゲームは二項目として届きます。あるタイトルの Switch 2 版と PS5 版、
あるいは別のタイトルの通常版と Switch 2 Edition です。*異なる*
プラットフォームのヒントが両方とも存在する場合、二行のまま残ります。この規則は、
重複排除の最初の版がまさにこの組を落とすことが計測されてから採用されました。

---

# 第 2 部 — ディスクの入力源

PC にインストールしてあるゲームと、GOG で所有しているがインストールしていない
ゲームも、同じレビュー文書に入れられます。この半分が短いのには十分な理由があり
ます。**鍵もモデルも写真も費用もない**からです。読むのは名前とローカルのファイル
だけで、実行はバイト単位で同じ結果を無料で繰り返します。

## インストール済みのゲーム

    dart run shelfscan_core:shelfscan scan-installs "C:\GOG Games" -o collection.review.json

オプション: `-o`、`--aliases`、`--library`、`--galaxy-db`。プロバイダのオプション
はありません。設定すべき画像認識の呼び出しがないからです。

ディレクトリ内のファイル名とフォルダ名、そしてゲームの隣に GOG のインストーラが
置いた `goggame-*.info` があればそれを読みます。**一階層下まで**で、それより深く
は行きません。ゲーム自身のフォルダの中で読むのは `goggame-*.info` だけです——ただ
しフォルダ名が「New Folder」のようなものである場合に限り、その中でゲーム名を
名乗っているインストーラを一つだけ読みます。ゲームの `data/`、`Saves/`、`Redist/`
の下がパイプラインに届くことはありません。それがレビュー一覧をゲームの一覧に保つ
ものです。

**この契約は内側からは強制できないので、実行のたびに何をしているかを述べます:**

    Reading C:\GOG Games: file and folder NAMES, plus any goggame-*.info beside them. No photo is read and no vision model is called. Nothing here can tell an application from a game by its name -- point this at a games folder only, and review every row before you export it.

これは真に受けてください。実在の `Downloads` フォルダに向けたところ、**出てきた
タイトルは全部がアプリケーションで、ゲームではありませんでした**。その
フォルダは私的なものであり、一覧も、中身の件数も公開しません。計測とはそれらへの
判定のことです。ファイル*名*の中に `NoteWellSetup.exe` と
`setup_moor_1.9.exe` を分けるものはなく、名前だけを読む規則にそれができることは
永遠にありません。

そのため、よく知られた個人用・システム用ディレクトリの短い固定の一覧は、正面から
拒否されます:

    Not a games folder: C:\Users\me\Downloads. This reads NAMES, and no rule reading a name tells NoteWellSetup.exe from setup_moor_1.9.exe -- run over a Downloads folder it titles every installer it finds, and not one of them is a game (T-0158). Point it at the directory your games are installed in.

ドライブのルートは同じ理由と、さらに悪い理由で拒否されます。その下のディレクトリ
が他のすべてになってしまう唯一のディレクトリだからです。

**ほかに言ってくること:**

    No games folder at C:\GOG Gamez
    Not a games folder: D:\setup.exe is a file -- scan-installs takes the directory your games are installed in, not one file
    Nothing to read in C:\GOG Games: the directory holds no file and no subdirectory.
    SKIPPED: <a goggame-*.info this shell could not read> -- <reason>

成功したときは、誰も暗算しなくて済む集計と、拒否したものの名前付きの一覧が出ます。
理由ごとにまとめられ、一つの理由につき最大二行なので、同種の拒否が四十件あっても
四十行ではなく二行です:

    Read 38 entry(ies) (31 folder(s), 5 loose file(s), 2 goggame-*.info): 29 game(s) found, 3 unresolved.
    Not a game: 9 entry(ies), named below and in "declined_entries"
      6 x not a game file
          <six names>
      3 x <another reason>
          <names>

## GOG のライブラリ、インストールの有無を問わず

    dart run shelfscan_core:shelfscan scan-library -o collection.review.json

オプション: `-o`、`--aliases`、`--galaxy-db`。位置引数はありません。Galaxy の
データベースは一つで、それが想定の場所にないときに `--galaxy-db` で指定します。

**Windows のみ**です。Galaxy が動くのがそこだからです。読むのは**このマシン上の
一つのファイルだけで、gog.com からは何も読みません**。ログインも OAuth もなく、
保存する資格情報も必要な資格情報もありません。

**これはアカウントではなく、最後の同期のキャッシュです。** Galaxy を最後に動かした
後に買ったゲームは入っておらず、その後削除したものがまだ載っていることもあります。
だから実行のたびに、それがどれだけ古いかを印字します:

    GOG Galaxy library as of <last sync timestamp> -- this is a local cache of the last sync, not a live read of the account: a game bought since then is missing and one removed since may still be listed. Nothing was read from gog.com and no credential was used.

DLC、Galaxy が隠している版、Galaxy に接続された他ストアの版は、黙って落とすので
はなく**名前を挙げて除外されます** — 実行は除外した行の種類を
それぞれ名で挙げます。

**うまくいかないとき:** データベースがない、または移動している場合は、何も見つから
なかったスキャンとして報告されるのではなく、専用のメッセージとともに終了コード 2
で終わります。また GOG がリーダーの下でスキーマを動かしていた場合は、失敗ではなく
警告が出ます。クエリ自体は成功しているので、これが読むテーブルはまだあるからです:

    WARN: this GOG Galaxy database is schema version 41; this reader was verified against 40. Check the titles below against Galaxy.

## 一度の実行、複数の入力源

ディスクで所有していて**かつ** PC にインストールもしてあるゲームは一つのゲーム
であり、その両方を一つの重複排除に通すのは一度の実行だけです:

    dart run shelfscan_core:shelfscan scan D:\photos --installs "C:\GOG Games" --library

これは、そのゲームが一行になっている**一つ**のレビュー文書を書きます。コマンドを
別々に実行すれば、誰にも突き合わせられない二つのファイルができ、しかも二つ目の
`-o` が一つ目を上書きします。

コマンドは自分より安い入力源を足せますが、高いものは決して足せません。
`scan-installs` は `--library` を取り（どちらも写真を読みません）、`scan-library`
はどちらも取らず、写真を持たない実行に写真を足すものはありません。それをやる実行が
`scan` であり、画像認識のオプションはすべてそこにあります。追加された入力源は
それぞれ自分の告知を保ちます。`--installs` はファイル名では分からないことを印字し、
`--library` はキャッシュの古さを印字します。

上のディスク系の経路はどれも、手順 4 が終わったのと同じ場所——
`collection.review.json` と次の一行——で終わります。

    Review file: collection.review.json -- set "status" per game, then export.

そこから先、**手順 5 から 8 はまったく同じ**です。確認し、直し、書き出し、取り
込みます。フォルダやライブラリから読んだ行も、写真から読んだ行とまったく同じよう
に確認します。理由も同じで、名前は証拠ではなく、書き出しは誤った行をまだ安く
取り除ける最後の地点だからです。

---

## 次に読むもの

- [`measurements.md`](measurements.md) — このプロジェクトが計測したすべて。測った
  うえでやらないと決めたものも含みます。これからやろうとしていることを扱っている
  節だけを読んでください（英語）。
- [`decisions/`](decisions/) — そうでなければ読者が驚くであろう決定と、それを
  決めた実測（英語）。
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — パイプライン、モジュールの地図、
  プラットフォームの境界（英語）。
- [`../.env.example`](../.env.example) — コマンドライン版が読む環境変数の完全な
  一覧と、各変数で空が何を意味するか。
