import Foundation

/// Plugin'e yazılan hook betikleri. İKİSİ DE içerik alanlarını (prompt, tool_input, tool_response, last_assistant_message,
/// transcript_path, compact_summary…) ASLA iletmez: yalnızca `AgentEvent.allowedKeys` anahtarları, kısaltılmış dize olarak.
/// `session_title` (oturum adı) tek "serbest metin" alanıdır: kontrol karakterleri temizlenir, 200 karakterle sınırlanır.
/// Betik her değiştiğinde `AgentPluginGenerator.version` artırılmalıdır (test özeti kilitler).
/// `pid` (yalnızca doğrulanmış tamsayı): hook komutunun üst süreci, ara kabuklar (sh/bash/zsh…) atlanarak en çok 4 seviye yukarıdaki
/// Claude Code süreci; bulunamazsa gönderilmez. Adalmon bununla oturumun süreci kapanınca listeyi hızla temizler.
/// `--dry-run`: ağa bağlanmadan süzülmüş yükü stdout'a yazar (testler bunu çalıştırır).
enum AgentPluginScripts {
    /// Birincil betik: /usr/bin/python3 (3.9 uyumlu, yalnızca standart kitaplık). Hata = sessiz çıkış (exit 0).
    static let python = #"""
    #!/usr/bin/python3
    # Adalmon "Claude ajanları": Claude Code hook olaylarını yerel Adalmon dinleyicisine iletir.
    # GİZLİLİK: yalnızca aşağıdaki izinli alanlar iletilir (oturum adı session_title dahil); istem, araç girdisi/çıktısı,
    # yanıt metni ve transkript ASLA.
    import json
    import os
    import sys
    import time

    MAX_LEN = 200
    SHELLS = ("sh", "bash", "zsh", "dash", "ksh", "fish", "tcsh", "csh")
    CONFIG = os.environ.get("ADALMON_AGENTS_CONFIG") or os.path.expanduser(
        "~/Library/Application Support/Adalmon/ClaudePlugin/config.json")


    def clean(value):
        if isinstance(value, str):
            value = value.strip()
            if value:
                return value[:MAX_LEN]
        return None


    def clean_title(value):
        # Oturum adı: kontrol karakterleri (ve yalnız vekil çiftleri) boşluğa çevrilir, boşluklar sadeleştirilir.
        if isinstance(value, str):
            value = "".join(" " if (ord(c) < 32 or 0x7F <= ord(c) <= 0x9F or 0xD800 <= ord(c) <= 0xDFFF) else c for c in value)
            value = " ".join(value.split())
            if value:
                return value[:MAX_LEN]
        return None


    def claude_pid():
        # Hook komutunun üst süreci; ara kabuksa (sh -c ...) bir üst sürece çık (en çok 4 seviye). Bulunamazsa None.
        try:
            import subprocess
            pid = os.getppid()
            for _ in range(5):
                if pid <= 1:
                    return None
                text = subprocess.run(["/bin/ps", "-o", "ppid=,comm=", "-p", str(pid)], stdout=subprocess.PIPE,
                                      stderr=subprocess.DEVNULL, timeout=1).stdout.decode("utf-8", "replace").strip()
                parts = text.split(None, 1)
                if len(parts) != 2 or not parts[0].isdigit():
                    return None
                name = os.path.basename(parts[1].strip()).lstrip("-")
                if name not in SHELLS:
                    return pid
                pid = int(parts[0])
        except Exception:
            pass
        return None


    def build(data):
        out = {}

        def put(key, value):
            value = clean(value)
            if value is not None:
                out[key] = value

        put("event", data.get("hook_event_name"))
        put("session_id", data.get("session_id"))
        put("agent_id", data.get("agent_id"))
        put("agent_type", data.get("agent_type"))
        put("tool_name", data.get("tool_name"))
        put("source", data.get("source"))
        put("model", data.get("model"))
        put("from_model", data.get("from_model"))
        put("to_model", data.get("to_model"))
        put("notification_type", data.get("notification_type"))
        put("reason", data.get("reason"))
        put("permission_mode", data.get("permission_mode"))
        title = clean_title(data.get("session_title"))
        if title is not None:
            out["session_title"] = title
        cwd = data.get("cwd")
        if isinstance(cwd, str) and cwd.strip():
            put("project", os.path.basename(cwd.rstrip("/")))
        # Alt ajan modeli: yalnızca Agent/Task aracının sonucundaki iki alan.
        if data.get("hook_event_name") == "PostToolUse" and data.get("tool_name") in ("Agent", "Task"):
            response = data.get("tool_response")
            if isinstance(response, str):
                try:
                    response = json.loads(response)
                except ValueError:
                    response = None
            if isinstance(response, dict):
                put("resolved_model", response.get("resolvedModel"))
                put("resolved_agent_id", response.get("agentId"))
        pid = claude_pid()
        if isinstance(pid, int) and 1 < pid < 2147483648:
            out["pid"] = pid
        out["ts"] = time.time()
        return out


    def main():
        try:
            data = json.loads(sys.stdin.read(4000000))
        except Exception:
            return 0
        if not isinstance(data, dict):
            return 0
        payload = build(data)
        if "event" not in payload or "session_id" not in payload:
            return 0
        if "--dry-run" in sys.argv:
            sys.stdout.write(json.dumps(payload, sort_keys=True))
            return 0
        try:
            import http.client
            with open(CONFIG, "r") as handle:
                config = json.load(handle)
            connection = http.client.HTTPConnection("127.0.0.1", int(config["port"]), timeout=1)
            connection.request("POST", "/v1/event", body=json.dumps(payload).encode("utf-8"), headers={
                "Content-Type": "application/json",
                "X-Adalmon-Token": str(config["token"]),
            })
            connection.getresponse().read()
            connection.close()
        except Exception:
            pass  # Adalmon kapalı olabilir: sessizce çık, Claude bozulmasın.
        return 0


    if __name__ == "__main__":
        try:
            code = main()
        except BaseException:
            code = 0
        sys.exit(0)
    """#

    /// Yedek betik: python3 yoksa. Yalnızca /bin/sh + /usr/bin/plutil + /usr/bin/curl; değerler güvenli karakterlere süzülür.
    static let shell = #"""
    #!/bin/sh
    # Adalmon "Claude ajanları" (yedek): python3 yoksa hook olaylarını yerel dinleyiciye iletir.
    # GİZLİLİK: yalnızca izinli alanlar iletilir (oturum adı session_title dahil); istem, araç girdisi/çıktısı, yanıt metni ve transkript ASLA.
    MODE="$1"
    CONFIG="${ADALMON_AGENTS_CONFIG:-$HOME/Library/Application Support/Adalmon/ClaudePlugin/config.json}"
    INPUT=$(/usr/bin/head -c 4000000)
    BODY=""
    SEP=""

    get() { printf '%s' "$INPUT" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null; }
    clean() { printf '%s' "$1" | /usr/bin/tr -cd 'A-Za-z0-9._:/@+ -' | /usr/bin/cut -c1-120; }
    # Oturum adı: kontrol karakterleri, çift tırnak ve ters eğik çizgi atılır (JSON/curl kaçışı gerekmesin); 200 karakter.
    clean_title() { printf '%s' "$1" | LC_ALL=en_US.UTF-8 /usr/bin/tr -d '[:cntrl:]"\\' | LC_ALL=en_US.UTF-8 /usr/bin/cut -c1-200; }
    add() {
      VALUE=$(clean "$2")
      if [ -n "$VALUE" ]; then
        BODY="$BODY$SEP\"$1\":\"$VALUE\""
        SEP=","
      fi
    }

    EVENT=$(get hook_event_name)
    TOOL=$(get tool_name)
    add event "$EVENT"
    add session_id "$(get session_id)"
    add agent_id "$(get agent_id)"
    add agent_type "$(get agent_type)"
    add tool_name "$TOOL"
    add source "$(get source)"
    add model "$(get model)"
    add from_model "$(get from_model)"
    add to_model "$(get to_model)"
    add notification_type "$(get notification_type)"
    add reason "$(get reason)"
    add permission_mode "$(get permission_mode)"
    TITLE=$(clean_title "$(get session_title)")
    if [ -n "$TITLE" ]; then BODY="$BODY$SEP\"session_title\":\"$TITLE\""; SEP=","; fi
    # Claude Code süreci: üst süreç; ara kabuksa (sh -c ...) bir üst süreç, en çok 4 seviye. Bulunamazsa pid gönderilmez.
    find_pid() {
      CUR=$PPID
      HOP=0
      while [ "$HOP" -le 4 ]; do
        case "$CUR" in ''|*[!0-9]*) return 1 ;; esac
        [ "$CUR" -gt 1 ] || return 1
        INFO=$(/bin/ps -o ppid=,comm= -p "$CUR" 2>/dev/null) || return 1
        set -f; set -- $INFO; set +f
        UP=$1
        [ $# -ge 2 ] || return 1
        shift
        COMM="$*"
        NAME=${COMM##*/}
        NAME=${NAME#-}
        case "$UP" in ''|*[!0-9]*) return 1 ;; esac
        case " sh bash zsh dash ksh fish tcsh csh " in *" $NAME "*) ;; *) FOUND_PID=$CUR; return 0 ;; esac
        CUR=$UP
        HOP=$((HOP + 1))
      done
      return 1
    }
    FOUND_PID=""
    find_pid
    CWD=$(get cwd)
    add project "$(/usr/bin/basename "${CWD:-/}" 2>/dev/null)"
    if [ "$EVENT" = "PostToolUse" ] && { [ "$TOOL" = "Agent" ] || [ "$TOOL" = "Task" ]; }; then
      add resolved_model "$(get tool_response.resolvedModel)"
      add resolved_agent_id "$(get tool_response.agentId)"
    fi
    case "$BODY" in *'"event"'*'"session_id"'*) ;; *) exit 0 ;; esac
    PID_FIELD=""
    case "$FOUND_PID" in ''|*[!0-9]*) ;; *) [ "$FOUND_PID" -gt 1 ] && [ "$FOUND_PID" -lt 2147483648 ] && PID_FIELD="\"pid\":$FOUND_PID," ;; esac
    BODY="{$BODY,${PID_FIELD}\"ts\":$(/bin/date +%s)}"

    if [ "$MODE" = "--dry-run" ]; then printf '%s' "$BODY"; exit 0; fi

    PORT=$(/usr/bin/plutil -extract port raw -o - "$CONFIG" 2>/dev/null)
    TOKEN=$(/usr/bin/plutil -extract token raw -o - "$CONFIG" 2>/dev/null)
    [ -n "$PORT" ] && [ -n "$TOKEN" ] || exit 0
    ESCAPED=$(printf '%s' "$BODY" | /usr/bin/sed 's/"/\\"/g')
    # Token komut satırında görünmesin diye curl yapılandırması stdin'den okunur.
    printf 'url = "http://127.0.0.1:%s/v1/event"\nheader = "X-Adalmon-Token: %s"\nheader = "Content-Type: application/json"\ndata-binary = "%s"\n' \
      "$PORT" "$TOKEN" "$ESCAPED" | /usr/bin/curl -s -o /dev/null --max-time 1 -K - >/dev/null 2>&1
    exit 0
    """#
}
