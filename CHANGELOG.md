# 変更履歴

このファイルの書式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に、
バージョン番号は [Semantic Versioning](https://semver.org/lang/ja/) に従います。

## [1.1.0] - 2026-09-06

### 追加

- セーブ枠の状況を確認する `saves` サブコマンドを追加しました。
  スキルが使うキャラクター名と、既存のセーブファイルの一覧を表示します。
- `doctor` が、設定ファイルにキャラクター名 (`OPTIONS=name:`) が
  指定されていない場合に警告するようになりました。

### 変更

- スキルが使うキャラクター名を `Claude` に固定しました
  (`assets/nethackrc` の `OPTIONS=name:Claude`)。
  NetHack のセーブは「キャラクター名 + uid」で識別されるため、
  これによりユーザー自身のゲームとセーブデータが分離されます。

  従来は名前を指定していなかったため、NetHack がログイン名を
  キャラクター名として使い、ユーザーが名前を指定せずに遊んだセーブと
  同じ枠を使う可能性がありました。

### 既存の利用者へ

キャラクター名が変わるため、**v1.0.0 でプレイ中のゲームには
スキルから到達できなくなります。** 続きを遊ぶ場合は、セーブファイルを
新しい名前にリネームしてください。

```bash
# セーブの場所は `nethack --showpaths` で確認できます
mv <playground>/save/<uid><旧キャラクター名>.Z <playground>/save/<uid>Claude.Z
```

リネームしたセーブはそのまま復元でき、以後のセーブも新しい名前で行われます。
ただし**ゲーム内のキャラクター名は元のまま**です(セーブに保持されているため)。
そのゲームが終了すれば、以降は `Claude` で統一されます。

## [1.0.0] - 2026-09-04

### 追加

- Claude Code に NetHack をプレイしてもらう Agent Skill 一式。
- NetHack **5.0.0** 対応。キー操作・拡張コマンド・画面の読み方を
  実機で検証した上で `references/commands.md` にまとめています。
- 画面を機械的に読むための NetHack 設定 (`assets/nethackrc`)。
  `NETHACKOPTIONS=@` で読み込むため、ユーザー個人の `~/.nethackrc` には
  触れません。
- cmux 操作のヘルパースクリプト (`scripts/cmux_nethack.sh`)。
  ペイン分割・キー送信・画面読み取り・環境点検などを行います。
- 2つの運転モード。
  - **通常モード** — 判断が必要な場面で手を止めてユーザーに確認します。
  - **完全放置モード** — 死亡またはゲームクリアまで続けます。
    停滞やゲームの異常終了を検知した場合は安全弁として停止します。

[1.1.0]: https://github.com/t-akuma/nethack_player/releases/tag/v1.1.0
[1.0.0]: https://github.com/t-akuma/nethack_player/releases/tag/v1.0.0
