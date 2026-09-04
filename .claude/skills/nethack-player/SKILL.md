---
name: nethack-player
description: Play NetHack autonomously in a visible cmux pane, driving the game via send-keys and screen capture. Use this skill whenever the user asks to play NetHack, start/resume a NetHack run, watch Claude play NetHack, or asks "what should I do next" / "is this safe" while a NetHack session is running. Also use for NetHack strategy, item identification, or monster questions even outside an active game. Always read the relevant references/ file before risky decisions — NetHack's monster glyphs, prayer rules, and item behaviors are easy to get subtly wrong from memory, and a wrong guess ends the run permanently. Also use when the user asks for a hands-off or unattended run ("完全放置", "play until you die", "keep going without me") — the skill defines both a normal mode that checks in at decision points and an unattended mode that runs until death or ascension; in either mode a stop/interrupt request from the user takes priority.
---

# NetHack Player

cmux 上で NetHack をプレイする。画面はユーザーが見えるペインに出したまま、Claude が「画面を読む → 判断する → キーを送る」を繰り返す。

NetHack はパーマデス(死んだらそのキャラは終わり)のゲームで、1手のミスが数時間の進行を無に帰す。**速く進めることより、正しく判断することを優先する。**

**対象は NetHack 5.0.0。** 3.6 とはキーバインドとオプションが一部違う(`v` が version ではなく chronicle、`number_pad` が真偽値でない、起動時にチュートリアルを聞かれる等)。3.6 の記憶で操作しないこと。差分は `references/commands.md` の「3.6 からの変更」にまとめてある。

## セットアップ

1. **点検する。**

   ```bash
   scripts/cmux_nethack.sh doctor
   ```

   cmux の内側にいるか、`nethack` のバージョン、スキルが使う設定ファイルの危険な設定、
   前回の異常終了で残ったロックファイルまで一度に見る。

2. **起動する。**

   ```bash
   scripts/cmux_nethack.sh start
   ```

   cmux のコマンド詳細は `references/cmux-usage.md`。

   **設定ファイルは `assets/nethackrc` を使う。`~/.nethackrc` は読まないし書き換えない。**
   `start` は `NETHACKOPTIONS='@<skill>/assets/nethackrc' nethack` で起動する。
   `@` 付きの `NETHACKOPTIONS` は「このファイルだけを設定として読む」指定なので、
   ユーザー個人の `~/.nethackrc`(職業、ペット名、キーバインドの好み)は
   一切混ざらない。**スキルのプレイのためにユーザーの設定を退避させる必要はない。**

   この分離は重要で、`assets/nethackrc` は「人が遊ぶための設定」ではなく
   「画面を機械的に読むための設定」である。色を消し、メニューを平坦にし、
   `altmeta` を切って `Escape` の暴発を防いでいる。人が遊ぶには不便な設定なので、
   ユーザーの既定にしてはいけない。

   ユーザー側から「自分で遊ぶときもこの設定にしたい」と言われた場合に限り
   `scripts/cmux_nethack.sh install-rc` で `~/.nethackrc` にも入れられる
   (既存はバックアップされるが、実行前に必ず確認する)。

3. **キャラクター作成に付き合う。** `assets/nethackrc` は role/race/gender/align を
   指定していないので、起動直後に順にメニューが出る:

   - `Shall I pick character's race, role, gender and alignment for you? [ynaq]`
   - `Pick a role or profession` (`a` Archeologist … `v` Valkyrie、末尾に `(end)`)
   - 続いて race / gender / alignment のメニュー

   **通常モードでは職業を Claude が勝手に決めない**(下記「運転モード」)。
   完全放置モードでユーザー指定が無い場合のみ、推奨(Valkyrie)を使う。
   推奨の根拠は `references/strategy.md`。

## プレイループのプロトコル

これが最重要セクション。この順序を守らないと入力が壊れる。

### 1. 画面を読む

```bash
scripts/cmux_nethack.sh read
```

読んだら**必ず次の順で確認する**。上から順に、「ゲームは通常のコマンドを
受け付ける状態か?」を潰していく。

1. **`--More--` が出ているか** → 出ていたら Space を送って進める。
   **`--More--` はメッセージの直後に出る。画面右下ではない**ので、1行目が長ければ
   2行目の行頭に出る。ここを飛ばすと以降の入力が全部ズレる。
2. **メニューが開いているか** → 最終行が `(end)` や `(1 of 2)` ならメニュー表示中。
   Escape で閉じる(複数ページは `>` で次へ)。
   **メニュー表示中はステータス行が隠れて HP が読めない。**判断の前に必ず閉じる。
3. **プロンプト待ちか** → `In what direction?` / `What do you want to use? [a-f or ?*]` /
   `Really attack? [yn] (n)` のような問いかけになっていたら、ゲームは**通常の移動コマンドを
   受け付けない状態**にある。問いに答えるか、Escape でキャンセルしてから次に進む。
   `[yes/no]` 形式のときは `y` ではなく `answer "yes"` が要る(`paranoid_confirmation` の設定による)。
4. **HP** → ステータス行の `HP:x(y)`。最大値の 1/3 以下なら他の判断より生存を優先(`references/dangers.md`)。
5. **状態異常** → `Conf` `Stun` `Blind` `Hallu` `Weak` `Ill` `FoodPois` などがあれば、
   通常の探索は中断して対処する。

`Unknown command ' '.` が出ていたら、`--More--` が無いのに Space を送ったということ。
自分の状態把握がずれている合図なので、`keys` を続けずに読み直す。

### 2. 判断する

うろ覚えで動かない。以下に該当したら該当ファイルを読んでから決める:

| 状況 | 読むファイル |
|---|---|
| 見慣れない文字のモンスターがいる / 戦うか逃げるか迷う | `references/dangers.md` |
| 未識別の巻物・薬・指輪・杖を使おうとしている | `references/identification.md` |
| HPが減った、状態異常、祈るか迷う | `references/dangers.md` |
| どこへ進むか、何を優先するか迷う | `references/strategy.md` |
| キー操作・拡張コマンドが思い出せない | `references/commands.md` |

ゲーム内でも引ける。`&` で「そのキーが何のコマンドか」、`#?` で拡張コマンド一覧、
`;` で「画面上のその文字が何か」。**推測して送るくらいなら、1手使って引く。**

### 3. キーを送る

**送信は4種類あり、混同すると致命的:**

| 用途 | コマンド | 改行 |
|---|---|---|
| ゲーム内の1文字コマンド | `scripts/cmux_nethack.sh keys "<文字列>"` | **付かない** |
| Escape / Return などの特殊キー | `scripts/cmux_nethack.sh key escape` | — |
| **拡張コマンド (`#pray` 等)** | `scripts/cmux_nethack.sh ext pray` | **`#pray` + Enter** |
| 文字列の回答("yes"、アイテム名など) | `scripts/cmux_nethack.sh answer "yes"` | 付く |
| シェルコマンド(ゲーム起動時のみ) | `scripts/cmux_nethack.sh run "nethack"` | 付く |

**拡張コマンドは Enter を送らないと実行されない。** `keys "#pray"` だけでは
入力途中のまま止まり、次に送ったキーがコマンド名の続きとして食われる。必ず `ext` を使う。

**meta キー(`M-p` 等)は使わない。** `M-p` は `#pray` の既定キーだが、cmux から
meta を送るのは Escape+文字の合成に頼ることになり、このスキルの `.nethackrc` は
その挙動(`altmeta`)を安全のため無効化している。拡張コマンドは必ず `ext <名前>`。

**一度に送るキーは1〜2アクション分まで。** まとめて10手送って後から画面を読む、は
やってはいけない。途中で `--More--` やプロンプトが挟まると残りが全部誤入力になる。

**長い移動は連打ではなく travel (`_`) を使う。** 目的地をカーソルで指定すれば
最短経路で1回のやりとりで着く。送信回数が減れば事故も減る(`references/commands.md`)。

### 4. 停滞を検知する

同じ画面が3回続けて返ってきたら、何かが詰まっている(プロンプト待ちに気付いていない、
メニューが開いたまま、送信先ペインが違う、ゲームが落ちている等)。
**同じ操作を繰り返さず、いったん手を止めて原因を調べる。**

順に試す: `read` で状態を見直す → `key escape` で開いているものを閉じる →
`keys "^R"` ではなく `key ctrl+r` で再描画 → それでもだめならユーザーに報告する。

`mention_walls` を有効にしてあるので、壁に向かって歩いていれば
"You can't move there." 等のメッセージが出る。画面が変わらない理由の切り分けに使う。

## 忘れやすい定期作業

- **レベルアップしたら `ext enhance`。** 上げられるスキルがあれば上げる。
  放置すると武器の命中・ダメージが伸びないまま深層に行くことになる。
- **階段でペットを隣に置く。** ただし `hilite_pet` は色表示なので **`read` の
  テキストにはペットの目印が出ない**。隣の `d` や `f` が味方かどうかは
  `;`(farlook)で "your kitten" のように確認する。
- **新しい階に着いたら `ext annotate`** で階の特徴を1行残す(祭壇、店、分岐など)。

## 進捗の記録

記録先は2つある。使い分ける。

**ゲーム内(セーブと一緒に残る。階の情報はこちらが正)**

- `ext overview`(`^O`): 訪れた階の一覧。祭壇・店・分岐階段は自動で注記される
- `ext annotate`: 今いる階に自分でメモを付ける
- `ext chronicle`(`v`): レベルアップや重要イベントの年代記
- `#name` / `C`: 「青い薬 = 治癒」と判明したらアイテム種別に名前を付ける

**外部ログ(セッションをまたぐ文脈。`~/.nethack_skill_log`)**

```bash
scripts/cmux_nethack.sh note "<内容>"
```

ゲームが覚えてくれないものだけを書く:

- 前回祈ったターン数(`#pray` の間隔管理に必須。ゲーム内には出ない)
- 危険な遭遇とその判断、避けた理由
- ユーザーとの取り決め(「Mines を優先する」等)
- 死亡とその原因

**セッションを再開するときは、まず `history` を読み、次にゲーム内の
`ext overview` と `ext chronicle` を見てから動く。**

## ユーザーへの報告

節目ごとに、チャット側で簡潔に状況を伝える(数行でよい。毎ターン実況しない)。あわせて cmux のサイドバーにも出す:

```bash
scripts/cmux_nethack.sh status "Dlvl:3 HP:14/18 Mines探索中"
```

危険な状況(HP低下、死亡)では `scripts/cmux_nethack.sh alert "..."` で通知を出す。

何を節目とみなし、どこで手を止めるかは運転モードによる(下記「運転モード」)。

## 運転モード

**通常モード**と**完全放置モード**の2つがある。**既定は通常モード。**
ユーザーが「完全放置で」「死ぬまで回して」等と明示したときだけ放置モードに入る。

どちらのモードでも、**ユーザーからの中断・終了の指示は最優先で従う**(「中断・終了」節)。

### 通常モード(既定)

ユーザーが見ている前提。区切りごとに手を止めて制御を返す。

**必ず止まってユーザーの返事を待つ:**

- キャラクター(種族/職業)の選択
- 死亡したとき — リスタートするかどうかは勝手に決めない
- 明らかにリスクの高い賭け(未識別の杖を自分に振る、瀕死で強敵に突っ込む、
  店主に手を出す、Sokoban で復帰不能になりうる岩を押す等)
- `install-rc` で `~/.nethackrc` を書き換えること(プレイには不要な操作)

**止まって報告するが、指示は待たずに続けてよい:**

- 新しい階層に到達 / 分岐(Mines, Sokoban)に入った
- レベルアップ、装備の更新、重要アイテムの入手
- 未識別アイテムの正体が判明した

**止まらない:** 通常の探索、雑魚との戦闘、拾得、ドアの開閉。

### 完全放置モード

ユーザーが席にいない前提。**死亡またはゲームクリア(昇天)まで続ける。**

このモードでは「ユーザーに確認する」が成立しない。確認の代わりに、
**判断に迷ったら常に安全側・保守側を選ぶ。** 具体的には:

- 未識別の杖を自分に振らない。未識別の指輪をいきなり装備しない
- 店主・平和的なモンスターに手を出さない
- HP が最大の 1/3 を切ったら、勝ちを狙わず離脱・回復を優先する
- 「行けるかもしれない」強敵は避ける。経験値より生存
- Sokoban で岩の押し方に確信が持てなければ、その階を諦めて先へ進む
- 職業はユーザー指定が無ければ `references/strategy.md` の推奨(Valkyrie)を使う

**このモードでも自動でリスタートはしない。** 死亡したらそこで終了し、
死因と到達点をまとめてユーザーに報告する。

**継続の仕組み。** 1回の応答で最後まで進むことはできないので、
`/loop` で繰り返し起動する形を取る。ユーザーが `/loop` を使っていない状態で
「完全放置で」と言われたら、`/loop` の使用を提案する。

**放置モードでも必ず止まる条件**(安全弁。ここで止まらないと事故が事故のまま進む):

1. **死亡 / クリア** — モードの終了条件
2. **停滞** — 同じ画面が3回続き、`references/commands.md` の手順で復帰できない
3. **ゲームが落ちている / ペインが応答しない**
4. **`--More--` でもプロンプトでもメニューでもない、解釈できない画面**

止まるときは、可能なら `S` でセーブしてから報告する。
セーブできない状態(死亡直後など)ならそのまま状況を報告する。

**放置中の可視化。** ユーザーが後から追えるように、節目で必ず残す:

```bash
scripts/cmux_nethack.sh status "Dlvl:5 HP:22/31 Minetown到達"
scripts/cmux_nethack.sh note   "Dlvl:5 Minetown 到達。祭壇あり。T:3200"
scripts/cmux_nethack.sh alert  "HP 6/31 まで低下。撤退中"   # 危険時のみ
```

`alert` は通知なので、乱発するとユーザーが放置できなくなる。
HP の危機的低下と死亡に限る。

## 中断・終了

**モードを問わず、ユーザーの指示が最優先。** 完全放置モードの最中でも、
「やめて」「中断して」「止まって」と言われたらその時点で打ち切る。
放置モードの終了条件(死亡/クリア)を理由に続行してはいけない。

手順:

1. `read` で画面を確認する。プロンプトやメニューが開いていたら Escape で閉じる
2. `keys "S"` を送る(セーブして終了)
3. 確認プロンプトが出たら画面の表記に従って答える
4. `scripts/cmux_nethack.sh note "セーブして中断"` を残す
5. `/loop` で回していた場合は、ループも止める

**プロセスを kill しない。** kill するとセーブされないだけでなく、プレイグラウンドに
レベルのロックファイル(`alock.0` など)が残り、次のゲームが始められなくなる。
残ってしまった場合は `scripts/cmux_nethack.sh locks` で場所を確認し、
**実行中のゲームが無いことを確かめてから**ユーザーに削除の可否を確認する。

再開は同じキャラ名で `start` すれば、セーブが自動的に復元される。
再開時はまず `history` と、ゲーム内の `ext overview` / `ext chronicle` を読んでから動く。
