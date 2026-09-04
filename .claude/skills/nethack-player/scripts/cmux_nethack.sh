#!/usr/bin/env bash
#
# cmux_nethack.sh - cmux 上の NetHack セッションを操作するヘルパー
#
# 重要: 送信は3種類あり、混同すると致命的。
#   keys   ゲーム内の1文字コマンド        改行を付けない
#   ext    拡張コマンド (#pray など)      名前 + Enter
#   run    シェルコマンド                  末尾に Enter
#
# NOTE: 対象は macOS 版 cmux の CLI (new-split / send / send-key / read-screen)。
#       cmux の制御ソケットは cmux 内で起動されたプロセスからしか接続できない。
#       cmux-tui (クラウドVM側の名詞ファースト CLI) とは文法が別物。
#       詳細は references/cmux-usage.md。
#
# NOTE: 対象ゲームは NetHack 5.0.0。コマンド体系は references/commands.md。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

STATE_FILE="${HOME}/.nethack_skill_surface"
LOG_FILE="${HOME}/.nethack_skill_log"
SETTLE_SECONDS="${NETHACK_SETTLE_SECONDS:-0.4}"

# このスキルがゲームに読ませる設定ファイル。
# 'start' は NETHACKOPTIONS=@<file> で起動するので、~/.nethackrc は読まれない。
# ユーザー個人の ~/.nethackrc をスキルが書き換えたり参照したりすることはない。
RC_FILE="${NETHACK_RC:-${SKILL_DIR}/assets/nethackrc}"

usage() {
  cat <<'EOF'
Usage:
  cmux_nethack.sh start              右側にペインを分割してnethackを起動
                                     (assets/nethackrc を NETHACKOPTIONS で直接読ませる。
                                      ~/.nethackrc には触れないし読まない)
  cmux_nethack.sh doctor             環境と設定ファイルを点検する(起動前に推奨)
  cmux_nethack.sh install-rc         [任意] assets/nethackrc を ~/.nethackrc にも導入する
                                     (ユーザーが自分で遊ぶときの既定にしたい場合だけ)

  cmux_nethack.sh keys "<chars>"     ゲーム内キーを送る(改行は付かない)
  cmux_nethack.sh key <keyname>      特殊キーを送る (escape / enter / space ...)
  cmux_nethack.sh ext <name>         拡張コマンドを送る  例: ext pray  → "#pray"+Enter
  cmux_nethack.sh answer "<text>"    文字列 + Enter を送る(yes/no 確認や名前入力用)
  cmux_nethack.sh run "<cmd>"        シェルコマンドを送る(末尾にEnterを送る)
  cmux_nethack.sh read               現在の画面を読み取る

  cmux_nethack.sh status "<text>"    cmuxサイドバーにステータス表示
  cmux_nethack.sh alert "<text>"     cmuxに通知を出す
  cmux_nethack.sh note "<text>"      進捗ログに1行追記
  cmux_nethack.sh history            進捗ログを表示
  cmux_nethack.sh attach <id>        既存ペインIDを手動で登録
  cmux_nethack.sh locks              放置されたロックファイルを調べる
EOF
}

die() { echo "エラー: $*" >&2; exit 1; }

# 保存済みのサーフェスIDを取得する。
# 注意: command substitution 内で exit しても親シェルは止まらないため、
#       呼び出し側では必ず空文字チェックを行うこと(この関数はチェック済みの値を返す)。
get_surface() {
  [[ -f "$STATE_FILE" ]] || die "NetHackセッションが未登録です。'start' を実行するか 'attach <id>' で登録してください。"
  local id
  id="$(cat "$STATE_FILE")"
  [[ -n "$id" ]] || die "状態ファイルが空です: $STATE_FILE"
  printf '%s' "$id"
}

# NetHack のプレイグラウンド(ロックファイル置き場)を推定する
playground_dir() {
  if [[ -n "${HACKDIR:-}" ]]; then printf '%s' "$HACKDIR"; return; fi
  local d
  for d in /opt/homebrew/share/nethack /usr/local/share/nethack /usr/games/lib/nethackdir /usr/lib/games/nethack; do
    [[ -d "$d" ]] && { printf '%s' "$d"; return; }
  done
  printf ''
}

cmd_attach() {
  local id="${1:-}"
  [[ -n "$id" ]] || die "ペイン/サーフェスIDを指定してください。"
  printf '%s' "$id" > "$STATE_FILE"
  echo "登録しました: $id"
}

# 任意。スキルのプレイには不要(start は NETHACKOPTIONS 経由で assets を直接読む)。
# ユーザーが「自分で遊ぶときもこの設定を既定にしたい」場合だけ使う。
# 既存があれば必ずバックアップを取り、上書き前に知らせる。
cmd_install_rc() {
  local src="${RC_FILE}"
  local dst="${HOME}/.nethackrc"
  [[ -f "$src" ]] || die "$src がありません。"
  echo "注意: スキルのプレイに ~/.nethackrc は不要です。'start' は $src を直接読みます。"

  if [[ -f "$dst" ]]; then
    if cmp -s "$src" "$dst"; then
      echo "~/.nethackrc は既にスキル版と同一です。"
      return
    fi
    local backup="${dst}.bak.$(date '+%Y%m%d%H%M%S')"
    cp "$dst" "$backup" || die "バックアップに失敗しました。"
    echo "既存の ~/.nethackrc を $backup に退避しました。"
    echo "  ユーザー固有の設定(name / role / pettype / fruit など)が入っていた場合は、"
    echo "  バックアップから新しい ~/.nethackrc の末尾に手で移してください。"
  fi
  cp "$src" "$dst" || die "コピーに失敗しました。"
  echo "~/.nethackrc を導入しました。'doctor' で確認してください。"
}

# 起動前の点検。ここで落としておけば、ゲーム中の事故が減る。
cmd_doctor() {
  local rc="$RC_FILE"
  local problems=0

  echo "── 実行環境 ──"
  if command -v cmux >/dev/null; then echo "  cmux: $(command -v cmux)"; else echo "  cmux: 見つかりません"; problems=$((problems+1)); fi
  if [[ -n "${CMUX_SURFACE_ID:-}" ]]; then
    echo "  cmux 内で実行中: yes (surface ${CMUX_SURFACE_ID})"
  else
    echo "  cmux 内で実行中: no  ← cmux の外からは制御ソケットに繋がりません"
    problems=$((problems+1))
  fi
  if command -v nethack >/dev/null; then
    echo "  nethack: $(nethack --version 2>&1 | head -1)"
  else
    echo "  nethack: 見つかりません"; problems=$((problems+1))
  fi

  echo "── 使用する設定ファイル ──"
  echo "  $rc"
  if [[ -f "${HOME}/.nethackrc" ]]; then
    echo "  (~/.nethackrc は存在しますが、NETHACKOPTIONS=@ 指定のため読まれません)"
  fi
  if [[ ! -f "$rc" ]]; then
    echo "  NG: このファイルがありません。"
    problems=$((problems+1))
  else
    # 値の否定形 (!foo) と肯定形を区別して見る
    check_rc() { # <正規表現> <NGメッセージ>
      if grep -Eq "$1" "$rc"; then echo "  NG: $2"; problems=$((problems+1)); fi
    }
    # altmeta は「書かれていて、かつ否定されていない」ときだけ NG
    if grep -E '^[^#]*altmeta' "$rc" | grep -qv '!altmeta'; then
      echo "  NG: altmeta が有効。Escape の直後に送った文字が meta コマンドとして暴発します(例: Escape→p が #pray)。'!altmeta' にしてください。"
      problems=$((problems+1))
    fi
    check_rc '^[^#]*!number_pad' \
      "'!number_pad' は 5.0.0 では設定エラーです。'number_pad:0' に直してください。"
    check_rc '^[^#]*windowtype:curses' \
      "windowtype が curses。メニューが罫線付きでマップに重なり、画面のパースが壊れます。'windowtype:tty' にしてください。"
    check_rc '^[^#]*paranoid_confirmation:[^#]*eating' \
      "paranoid_confirmation の 'eating' は設定エラーです(Guidebook の誤記)。'eat' に直してください。"

    check_present() { # <正規表現> <NGメッセージ>
      if ! grep -Eq "$1" "$rc"; then echo "  NG: $2"; problems=$((problems+1)); fi
    }
    check_present '^[^#]*OPTIONS=.*!tutorial' \
      "'!tutorial' が無い。起動直後にチュートリアルの可否メニューが出ます(5.0 の新仕様)。"
    check_present '^[^#]*OPTIONS=.*windowtype:tty' \
      "'windowtype:tty' の明示が無い。既定が curses のビルドでは画面が壊れます。"
    # paranoid_confirmation は指定した瞬間に既定値 (pray swim trap) を置き換える。
    # 行が無いなら既定が効いているので問題なし。行がある場合だけ中身を見る。
    if grep -Eq '^[^#]*paranoid_confirmation:' "$rc"; then
      local pc; pc="$(grep -E '^[^#]*paranoid_confirmation:' "$rc")"
      local kw
      for kw in swim trap pray; do
        if ! printf '%s' "$pc" | grep -q "$kw"; then
          echo "  NG: paranoid_confirmation に '$kw' が無い。この設定は既定値 (pray swim trap) を追加ではなく置き換えるので、書かないと安全弁が消えます。"
          problems=$((problems+1))
        fi
      done
    fi

    [[ $problems -eq 0 ]] && echo "  問題なし。"
  fi

  echo "── 放置ロック ──"
  cmd_locks

  echo
  if [[ $problems -eq 0 ]]; then
    echo "点検終了: 問題は見つかりませんでした。"
  else
    echo "点検終了: ${problems} 件の指摘があります。"
  fi
}

# 前回の nethack が kill された場合、レベルのロックファイルが残り、
# 新しいゲームが始められなくなる。削除は破壊的なので報告だけ行う。
cmd_locks() {
  local dir; dir="$(playground_dir)"
  if [[ -z "$dir" ]]; then
    echo "  プレイグラウンドの場所を特定できませんでした(HACKDIR を設定してください)。"
    return
  fi
  local found
  found="$(ls "$dir" 2>/dev/null | grep -E '^[a-z]lock\.[0-9]+$' || true)"
  if [[ -z "$found" ]]; then
    echo "  なし ($dir)"
  else
    echo "  $dir に残存ロックがあります:"
    printf '    %s\n' $found
    echo "  実行中のゲームが無いことを確認してから削除してください:"
    echo "    ls $dir/[a-z]lock.[0-9]*"
    echo "  ゲームは kill せず 'S' でセーブすれば、これは残りません。"
  fi
}

cmd_start() {
  command -v cmux >/dev/null || die "cmux が見つかりません。"
  [[ -n "${CMUX_SURFACE_ID:-}" ]] \
    || die "cmux の外で実行されています。cmux の制御ソケットは cmux 内で起動されたプロセスからしか接続できません。"
  command -v nethack >/dev/null || echo "警告: nethack コマンドが見つかりません。インストールが必要かもしれません。" >&2
  [[ -f "$RC_FILE" ]] || die "設定ファイルがありません: $RC_FILE"

  # --focus は既定 false。呼び出し元(Claude が動いているペイン)からフォーカスを奪わない。
  local split_json
  split_json="$(cmux new-split right --json)" \
    || die "ペインの分割に失敗しました。'cmux ping' でソケット疎通を確認してください。"

  local surface_id
  surface_id="$(printf '%s' "$split_json" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
v = d.get("surface_id") or d.get("surface_ref")
if v:
    print(v)' 2>/dev/null)"

  if [[ -z "$surface_id" ]]; then
    die "新しいペインのIDを取得できませんでした。分割されたペインで 'echo \$CMUX_SURFACE_ID' を確認し、'attach <id>' で手動登録してください。"
  fi

  printf '%s' "$surface_id" > "$STATE_FILE"
  echo "NetHack用サーフェス: $surface_id"

  # NETHACKOPTIONS=@<file> は「その1ファイルだけを設定として読む」指定で、
  # ~/.nethackrc は読まれなくなる。スキルの設定とユーザー個人の設定が混ざらない。
  cmd_run "NETHACKOPTIONS='@${RC_FILE}' nethack"
  echo "設定: $RC_FILE (~/.nethackrc は読まれません)"
  echo "起動しました。'read' で画面を確認してください。"
}

# ゲーム内キー入力。'cmux send' は改行を付けない。
# 注意: send は \n \r \t だけをエスケープとして解釈する。
cmd_keys() {
  local chars="${1:-}"
  [[ -n "$chars" ]] || die "送信するキーを指定してください。"
  local id; id="$(get_surface)" || exit 1
  cmux send --surface "$id" -- "$chars"
}

# 特殊キー(escape, enter, space, ctrl+c など)。キー名は小文字化して解釈される。
cmd_key() {
  local keyname="${1:-}"
  [[ -n "$keyname" ]] || die "キー名を指定してください (escape / enter / space ...)。"
  local id; id="$(get_surface)" || exit 1
  cmux send-key --surface "$id" -- "$keyname"
}

# 拡張コマンド。'#' + 名前 + Enter。Enter を忘れると実行されずに入力待ちのまま残る。
# meta キー (M-p など) は使わない。altmeta 経由の meta は Escape と衝突して危険。
cmd_ext() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "拡張コマンド名を指定してください (例: pray, enhance, overview)。"
  name="${name#\#}"
  local id; id="$(get_surface)" || exit 1
  cmux send --surface "$id" -- "#${name}"
  cmux send-key --surface "$id" -- enter
}

# 文字列 + Enter。"yes" を要求する確認プロンプトや #name の名前入力に使う。
cmd_answer() {
  local text="${1:-}"
  [[ -n "$text" ]] || die "送信する文字列を指定してください。"
  local id; id="$(get_surface)" || exit 1
  cmux send --surface "$id" -- "$text"
  cmux send-key --surface "$id" -- enter
}

# シェルコマンド。テキストを送ってから Enter キーを送る。
cmd_run() {
  local command_line="${1:-}"
  [[ -n "$command_line" ]] || die "コマンドを指定してください。"
  local id; id="$(get_surface)" || exit 1
  cmux send --surface "$id" -- "$command_line"
  cmux send-key --surface "$id" -- enter
}

cmd_read() {
  local id; id="$(get_surface)" || exit 1
  # 画面が描画し終わるのを少し待つ
  sleep "$SETTLE_SECONDS"
  local out
  # スクロールバックではなく現在のビューポートを取る(TUI なので既定でよい)
  out="$(cmux read-screen --surface "$id")" \
    || die "画面を読み取れませんでした。サーフェスIDと 'cmux ping' を確認してください。"
  printf '%s\n' "$out"
}

cmd_status() {
  cmux set-status nethack "${1:-}" --icon hammer 2>/dev/null || true
}

cmd_alert() {
  local text="${1:-}"
  [[ -n "$text" ]] || die "通知内容を指定してください。"
  cmux notify --title "NetHack" --body "$text" >/dev/null 2>&1 || true
  cmux log --level warning --source nethack -- "$text" >/dev/null 2>&1 || true
}

cmd_note() {
  local text="${1:-}"
  [[ -n "$text" ]] || die "記録する内容を指定してください。"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$text" >> "$LOG_FILE"
  echo "記録しました。"
}

cmd_history() {
  [[ -f "$LOG_FILE" ]] || { echo "(まだ記録はありません)"; return; }
  cat "$LOG_FILE"
}

main() {
  local action="${1:-}"
  shift || true
  case "$action" in
    start)      cmd_start ;;
    doctor)     cmd_doctor ;;
    install-rc) cmd_install_rc ;;
    attach)     cmd_attach "${1:-}" ;;
    keys)       cmd_keys "${1:-}" ;;
    key)        cmd_key "${1:-}" ;;
    ext)        cmd_ext "${1:-}" ;;
    answer)     cmd_answer "${1:-}" ;;
    run)        cmd_run "${1:-}" ;;
    read)       cmd_read ;;
    status)     cmd_status "${1:-}" ;;
    alert)      cmd_alert "${1:-}" ;;
    note)       cmd_note "${1:-}" ;;
    history)    cmd_history ;;
    locks)      cmd_locks ;;
    ""|-h|--help|help) usage ;;
    *)          usage; exit 1 ;;
  esac
}

main "$@"
