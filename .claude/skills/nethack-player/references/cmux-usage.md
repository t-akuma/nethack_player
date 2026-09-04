# cmux でのNetHack操作

cmux は macOS のターミナルマルチプレクサ。Unix ソケット経由の CLI でペインの作成・キー送信・画面読み取りができる。

**通常は `scripts/cmux_nethack.sh` を経由して使う。** 以下は、その中身と、直接 cmux を叩くときの正しいコマンドの説明。

情報源はローカルの `cmux <command> --help` と、上流の
`https://github.com/manaflow-ai/cmux/blob/main/docs/cli-contract.md` /
`https://github.com/manaflow-ai/cmux/blob/main/skills/cmux/SKILL.md`。
`cmux docs api` を実行すると最新版の取得コマンドが表示される。

## 大前提: cmux の中から実行すること

cmux の制御ソケットは**cmux 内で起動されたプロセスからしか接続できない**。cmux 外のターミナルで叩くと、コマンド名が正しくても次で落ちる:

```
Error: ERROR: アクセスが拒否されました。cmux 内で起動されたプロセスのみ接続できます
```

つまり、このスキルを動かす Claude Code 自体が cmux のターミナルペインで起動している必要がある。判定は環境変数で行う:

```bash
[[ -n "${CMUX_SURFACE_ID:-}" ]] || echo "cmux の外にいる"
cmux ping            # ソケット疎通確認
cmux identify --json # 呼び出し元の window/workspace/surface
```

cmux が各ターミナルに自動で入れる変数:

| 変数 | 意味 |
|---|---|
| `CMUX_SURFACE_ID` | そのターミナル自身のサーフェスID。`--surface` の既定値 |
| `CMUX_WORKSPACE_ID` | 所属ワークスペースID。`--workspace` の既定値 |
| `CMUX_SOCKET_PATH` | ソケットパスの上書き |

## 用語

cmux の階層は **window > workspace > pane > surface(タブ)**。ターミナル1つが1 surface で、キー送信・画面読み取りの単位は surface。

ハンドルは UUID でも短縮ref (`surface:3` / `pane:1` / `workspace:2`) でも渡せる。出力は既定で ref、`--id-format uuids|both` を付けると UUID も出る。

## ペインを分割して NetHack を起動する

```bash
# 右に分割。--focus は既定 false なのでフォーカスは呼び出し元に残る
cmux new-split right --json
```

`new-split` は成功時、テキスト出力なら `OK surface:<n> ...`、`--json` なら `surface_id` / `surface_ref` を含むオブジェクトを返す。新しいサーフェスIDはここから取る:

```bash
surface="$(cmux new-split right --json \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["surface_id"])')"
```

取れなかったときは、分割されたペインの中で `echo $CMUX_SURFACE_ID` を確認して手動登録する:

```bash
scripts/cmux_nethack.sh attach "<そこで表示された値>"
```

ゲームの起動は「テキストを送る → Enter キーを送る」の2手に分けるのが確実:

```bash
cmux send --surface "$surface" -- "nethack"
cmux send-key --surface "$surface" -- enter
```

## キー送信の重要な区別

NetHack は1文字コマンドのゲームなので、**改行の有無が挙動を変える**。

| コマンド | 送るもの | 改行 |
|---|---|---|
| `cmux send --surface <id> -- "<text>"` | テキストをそのまま入力 | **付かない** |
| `cmux send-key --surface <id> -- <key>` | 1つのキーイベント | — |

`cmux send` は改行を**付けない**。`--no-newline` に相当するオプションは存在しないし、必要もない。ゲーム内キーはそのまま `send` でよい。

`send` が解釈するエスケープは `\n` と `\r`(どちらも Enter)、`\t`(Tab)だけ。それ以外のバックスラッシュは素通しなので、NetHack の `\`(既知アイテム一覧)は `cmux send -- '\'` で送れる。ただし `\` の直後に `n` `r` `t` が続く文字列は誤解釈されるので、その場合は1文字ずつ送る。

`send` の残り引数は**スペースで連結される**。複数キーをまとめて送るときは必ず1つのクォートでくくること:

```bash
cmux send --surface "$s" -- "hjkl"      # OK: h j k l の4キー
cmux send --surface "$s" -- h j k l     # NG: "h j k l" になりスペースが混ざる
```

先頭が `-` の文字(NetHack の `-` コマンドなど)は `--` の後に置く。

### send-key のキー名

小文字化されてから解釈されるので大文字小文字は問わない。

`enter` / `return`、`escape` / `esc`、`space`、`tab`、`backtab`、`backspace`、`delete`、`up` / `down` / `left` / `right`、`home`、`end`、`pageup`、`pagedown`、および単一の英字。
修飾キーは `+` でも `-` でも連結でき、`ctrl` / `control`、`shift`、`alt` / `option`、`cmd` / `command` が使える(例 `ctrl+c`、`ctrl-c`)。

Escape は `send` では送れないので必ず `send-key escape`。`--More--` を進める Space は `send-key space` でも `cmux send -- " "` でもよい。

## 画面読み取り

```bash
cmux read-screen --surface "$surface"
```

- 標準出力に**画面テキストだけ**を出す(ヘッダ等は付かない)。`--json` にすると `text` などを含むオブジェクトになる。
- 既定は**現在描画されている画面(ビューポート)のみ**。NetHack は TUI なのでこれが正しい。`--scrollback` / `--lines <n>` はスクロールバックを含めるオプションで、TUI の読み取りには使わない。
- `cmux capture-pane` は同じフラグを取る tmux 互換エイリアス。
- 画面サイズは **24行×80列固定ではなく、ペインの実サイズ**。NetHack は最低 80×24 を必要とするので、分割で細くなりすぎたらペイン幅を広げる。
- キー送信直後は描画が終わっていないことがあるため、スクリプトは読み取り前に短い待機を入れている。反応が遅い環境では `NETHACK_SETTLE_SECONDS=1.0` のように環境変数で伸ばせる。

## 送信先を必ず明示する

`--surface` を省くと `$CMUX_SURFACE_ID`、つまり **Claude 自身が動いているペイン**が既定のターゲットになる。省略すると自分の端末にゲームキーを打ち込むことになるので、ゲーム操作では必ず `--surface <NetHackのサーフェスID>` を明示する。

## ステータスと通知

サイドバー表示は workspace スコープで、既定は `$CMUX_WORKSPACE_ID`。

```bash
# ステータスピル(key ごとに1つ。同じ key で上書き、clear-status で消す)
cmux set-status nethack "Dlvl:3 HP:14/18 Mines探索中" --icon hammer --color "#ff9500"
cmux clear-status nethack
cmux list-status

# サイドバーのログ行(通知ではない)
cmux log --level warning --source nethack -- "HP 5/18 撤退中"

# 実際の通知はこちら
cmux notify --title "NetHack" --body "HP 5/18 撤退中"
```

`--level` は `info` / `progress` / `success` / `warning` / `error`。`--icon` は SF Symbols 名(`hammer` / `sparkle` など)で、存在しない名前を渡すとアイコンが出ない。

サイドバーの表示はユーザーが横目で進捗を追うためのもの。毎ターン更新せず、節目でだけ更新する。

## 紛らわしい別物: cmux-tui

上流リポジトリの `cmux-tui/` は別プロダクト(Rust 製の TUI マルチプレクサ)で、CLI 文法が名詞ファーストにまったく異なる:

```bash
cmux terminal <term_id> screen read
cmux terminal <term_id> keys ctrl+c
cmux pane <pane_id> split --right
```

これはクラウドVM / リモートマシン側で動く CLI で、ローカルの `cmux` バイナリはこの文法を受け付けない(ローカルからは `cmux vm terminal read/send/wait` 経由で触る)。`cmux-tui/docs/` や `cmux-tui/spec/cli.md` を読むときは、この skill が対象にしているローカル CLI とは別物だと意識すること。

なお `cmux-tui/spec/resource-api-v2.md` には `keys ctrl-c` という例があるが、cmux-tui 側のキー解釈は `+` 区切りのみなので `ctrl+c` が正しい(ローカルの `cmux send-key` は `-` も受け付ける)。
