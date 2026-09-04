# nethack-player

Claude Code に NetHack をプレイしてもらう [Agent Skill](https://docs.claude.com/en/docs/claude-code/skills) です。

Claude が「画面を読む → 判断する → キーを送る」を繰り返してダンジョンに潜ります。
プレイ画面は cmux の隣のペインに出しっぱなしになるので、**あなたは横で眺めているだけ**で構いません。

```
┌──────────────────────┬──────────────────────┐
│ Claude Code          │ NetHack              │
│                      │                      │
│ > 完全放置でプレイして │   ------------       │
│                      │   |....d@....|       │
│ Dlvl:3 に到達。       │   |..........|       │
│ 祭壇を見つけたので     │   ..../......|       │
│ 未識別の薬を判定中。   │   ------------       │
│                      │ Dlvl:3 HP:18(24) ... │
└──────────────────────┴──────────────────────┘
   ← Claude が動くペイン      ← 送信先のペイン
```

NetHack はパーマデス(死んだらそのキャラは終わり)のゲームです。
このスキルは速さより**正しく判断すること**を優先するように書かれています。

## 動作環境

| 必要なもの | 補足 |
|---|---|
| macOS (Sonoma 以降) | cmux の要件 |
| [cmux](https://cmux.com) | ペインの分割・キー送信・画面読み取りに使う |
| NetHack **5.0.0** | 5.0.0 の実機で検証済み。3.6 系はキーバインドとオプションが異なるため未対応 |
| Claude Code | cmux のターミナルペイン内で起動すること |

## インストール

### 1. cmux

```bash
brew tap manaflow-ai/cmux
brew install --cask cmux
```

### 2. NetHack

```bash
brew install nethack
```

バージョンを確認します。`5.0.0` と出れば OK です。

```bash
nethack --version
```

### 3. このリポジトリ

```bash
git clone git@github.com:t-akuma/nethack_player.git
cd nethack_player
```

スキルは `.claude/skills/nethack-player/` に入っています。
**プロジェクトスコープのスキル**なので、インストール作業は不要です。
このディレクトリで Claude Code を起動すれば自動的に読み込まれます。

## 使い方

**cmux のターミナルから**、クローンしたディレクトリで Claude Code を起動します。

```bash
cd nethack_player
claude
```

cmux の中で起動することが必須です。cmux の制御ソケットは cmux 内で起動された
プロセスからしか接続できないため、通常のターミナルから起動すると動きません。

あとは日本語で指示するだけです。

```
NetHack をプレイして
```

Claude が環境を点検し、ペインを右に分割して NetHack を起動します。
フォーカスは Claude 側のペインに残るので、そのまま会話を続けられます。

プレイ中に話しかけることもできます。

```
いまの状況は?
それは安全?
その敵は避けたほうがいいんじゃない?
```

## 運転モード

2つあります。**指定しなければ通常モード**です。

### 通常モード(既定)

あなたが見ている前提で、区切りごとに手を止めて判断を仰ぎます。

- **止まって返事を待つ** — 職業の選択、死亡時、リスクの高い賭け(未識別の杖を自分に振る、瀕死で強敵に挑む、店主に手を出す、Sokoban で復帰不能になりうる岩を押す)
- **報告するが待たずに続ける** — 新しい階層への到達、レベルアップ、装備の更新、アイテムの識別
- **止まらない** — 通常の探索、雑魚との戦闘、拾得

### 完全放置モード

```
完全放置でプレイして
```

**死亡またはゲームクリア(昇天)まで続けます。** 席を外していても進みます。

このモードでは「あなたに確認する」ができないので、代わりに
**判断に迷ったら常に安全側を選ぶ**というルールに置き換わります。
未識別の杖を自分に振らない、HP が 1/3 を切ったら勝ちを狙わず離脱する、といった具合です。

放置モードでも次の場合は必ず止まります。事故を事故のまま進行させないための安全弁です。

1. 死亡 / クリア(モードの終了条件)
2. 同じ画面が3回続き、復帰手順でも直らない(停滞)
3. ゲームが落ちている / ペインが応答しない
4. `--More--` でもプロンプトでもメニューでもない、解釈できない画面

長時間まわす場合は `/loop` と組み合わせます。1回の応答で死ぬまで到達することは
できないため、繰り返し起動する仕組みが必要です。

```
/loop /nethack-player 続きをプレイ
```

### 中断・終了

**モードを問わず、あなたの指示が最優先です。** 完全放置モードの最中でも、

```
やめて
```

と言えばその時点で打ち切ります。ゲーム内の `S`(セーブ)で安全に終了するので、
続きは後から再開できます。急ぐときは Esc で割り込んでください。

再開するときは:

```
NetHack を再開して
```

同じキャラクター名のセーブが自動的に復元されます。

## 最初のキャラクターメイキング

初回起動時、NetHack が職業・種族・性別・属性を順に聞いてきます。

**通常モードでは、Claude は職業を勝手に決めません。** 好みがあるかもしれないからです。
「おまかせで」と言えば推奨構成を選びます。

推奨は **Valkyrie**(人間・中立)です。HP と近接性能が高く、初期装備だけで序盤を
戦い抜けるため、アイテムの識別に失敗しても事故りにくいという理由です。
Samurai は初期の弓矢で floating eye を遠距離処理できる点が強く、
Barbarian は毒耐性を最初から持ちます。

Wizard / Priest(呪文と魔力の管理が複雑)、Tourist / Archeologist(初期装備が貧弱)、
Healer(戦闘力が低い)は、自動プレイでは事故率が上がるため避けています。

## 設定ファイルについて

### あなたの `~/.nethackrc` には触れません

このスキルは専用の設定ファイル `assets/nethackrc` を使います。起動時に

```bash
NETHACKOPTIONS='@<skill>/assets/nethackrc' nethack
```

の形で読ませるため、**あなた個人の `~/.nethackrc` は読まれも書き換えられもしません。**
普段ご自身で遊ぶときの設定(職業の好み、ペットの名前、キーバインド)はそのままで大丈夫です。

### なぜ専用の設定が要るのか

`assets/nethackrc` は「人が遊ぶための設定」ではなく
**「画面を機械的に読むための設定」**です。人間が遊ぶには不便なので、
あなたの既定にはしないでください。主な内容は次のとおりです。

**画面をテキストとして安定させる**

- `windowtype:tty` — curses だとメニューが罫線付きのポップアップとしてマップに重なり、画面のパースが壊れます
- `!color` / `symset:default` / `!menu_overlay` — 装飾を落として構造を単純にする
- `runmode:teleport` — 走行中の途中経過を描画しない。移動完了後の画面だけを読める

**入力事故を防ぐ**

- `!altmeta` — **これが最重要です。** altmeta が有効だと NetHack は「Escape の次に来た文字」を meta キーとして解釈します。時間差は関係ありません。このスキルは「プロンプトを Escape で取り消してから次のキーを送る」ため、有効のままだと `Escape` → `p` が `#pray`(困っていないのに祈る = 神の怒り)、`Escape` → `X` が `#exploremode`(以後スコアが付かない)として暴発します
- `paranoid_confirmation:pray swim trap attack Remove wand-break eat Confirm` — 水や溶岩への進入、既知の罠、平和的なモンスターへの攻撃に確認を挟む。`Confirm` により重要な確認は `y` ではなく `yes` のフルタイプが必要になるので、キーが1つ暴発しても致命的な操作は確定しません
- `!tutorial` — NetHack 5.0 で追加された起動時のチュートリアル選択を抑止

**状況を文字で拾えるようにする**

- `mention_walls` / `mention_decor` — 壁にぶつかった、階段や祭壇に乗った、をメッセージで通知。停滞の検知に効きます
- `autodescribe` / `whatis_coord:m` — 位置選択中にカーソル下の説明と座標を表示

### 自分で遊ぶときもこの設定にしたい場合

```bash
.claude/skills/nethack-player/scripts/cmux_nethack.sh install-rc
```

`~/.nethackrc` にコピーします(既存のファイルは自動でバックアップされます)。
プレイには不要な操作なので、必要な場合だけどうぞ。

## ヘルパースクリプト

Claude が使うコマンドです。手動で叩くこともできます。

```bash
cd .claude/skills/nethack-player
```

| コマンド | 動作 |
|---|---|
| `scripts/cmux_nethack.sh doctor` | 環境と設定ファイルを点検する(起動前に推奨) |
| `scripts/cmux_nethack.sh start` | ペインを分割して NetHack を起動 |
| `scripts/cmux_nethack.sh read` | 現在の画面を読み取る |
| `scripts/cmux_nethack.sh keys "<文字>"` | ゲーム内キーを送る(改行を付けない) |
| `scripts/cmux_nethack.sh key escape` | 特殊キーを送る |
| `scripts/cmux_nethack.sh ext pray` | 拡張コマンドを送る(`#pray` + Enter) |
| `scripts/cmux_nethack.sh answer "yes"` | 文字列 + Enter を送る |
| `scripts/cmux_nethack.sh status "<文>"` | cmux のサイドバーにステータス表示 |
| `scripts/cmux_nethack.sh note "<文>"` | 進捗ログに追記(`~/.nethack_skill_log`) |
| `scripts/cmux_nethack.sh history` | 進捗ログを表示 |
| `scripts/cmux_nethack.sh locks` | 放置されたロックファイルを調べる |

## トラブルシューティング

### まず `doctor`

```bash
.claude/skills/nethack-player/scripts/cmux_nethack.sh doctor
```

cmux の内側にいるか、NetHack のバージョン、設定ファイルの危険な設定、
残存ロックファイルまで一度に点検します。

### 「アクセスが拒否されました」と出る

cmux の外で Claude Code を起動しています。cmux のターミナルペインから起動してください。
判定は環境変数で行えます。

```bash
echo $CMUX_SURFACE_ID   # 空なら cmux の外にいる
```

### 新しいゲームが始められない

前回の NetHack が正常終了せず(kill された等)、ロックファイルが残っています。

```bash
scripts/cmux_nethack.sh locks
```

実行中のゲームが無いことを確認してから、表示された `[a-z]lock.N` を削除してください。
**ゲームは kill せず `S` でセーブすれば、これは残りません。**

### 画面が崩れる

- ペインが狭すぎませんか。NetHack は最低 80x24 を必要とします
- `windowtype` が curses になっていませんか(`doctor` が検出します)

## リポジトリ構成

```
.claude/skills/nethack-player/
├── SKILL.md                    プレイのプロトコル(Claude が最初に読む)
├── references/
│   ├── commands.md             NetHack 5.0.0 のキー操作・拡張コマンド・画面の読み方
│   ├── dangers.md              危険なモンスター、祈りのルール、状態異常への対処
│   ├── identification.md       アイテム識別の手順
│   ├── strategy.md             職業選択、ダンジョン構造、序盤の方針
│   └── cmux-usage.md           cmux CLI の使い方
├── scripts/
│   └── cmux_nethack.sh         cmux 操作のヘルパー
└── assets/
    └── nethackrc               画面を機械的に読むための NetHack 設定
```

攻略知識は `references/` に分けてあります。Claude は危険な判断の前に
該当ファイルを読んでから動きます。モンスターの文字、祈りの間隔、アイテムの挙動は
記憶だけでは間違えやすく、一度の誤りが数時間の進行を無に帰すためです。

## ライセンス

MIT License. 詳細は [LICENSE](LICENSE) を参照してください。
