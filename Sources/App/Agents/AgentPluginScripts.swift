import Foundation

/// Plugin'e yazılan hook betikleri. İKİSİ DE içerik alanlarını (prompt, tool_input, tool_response, last_assistant_message,
/// transcript_path, compact_summary…) ASLA iletmez: yalnızca `AgentEvent.allowedKeys` anahtarları, kısaltılmış dize olarak.
/// `session_title` (oturum adı) tek "serbest metin" alanıdır: kontrol karakterleri temizlenir, 200 karakterle sınırlanır.
/// Betik her değiştiğinde `AgentPluginGenerator.version` artırılmalıdır (test özeti kilitler).
/// `pid` (yalnızca doğrulanmış tamsayı): hook komutunun üst süreci, ara kabuklar (sh/bash/zsh…) atlanarak en çok 4 seviye yukarıdaki
/// Claude Code süreci; bulunamazsa gönderilmez. Adalmon bununla oturumun süreci kapanınca listeyi hızla temizler.
/// `target` (yalnızca PreToolUse ve config.json'da `showTargets: true` ise): Edit/Write/MultiEdit/NotebookEdit/Read için dosya yolunun SON
/// bileşeni (en çok 40 karakter, kontrol karakteri yok); Bash için komutun İLK gerçek kelimesi (yalnızca ^[A-Za-z0-9_.+-]{1,24}$;
/// env atamaları ve sudo gibi önekler atlanır; yol/argüman/tırnaklı ya da özel karakterli bir şey görülürse hiçbir şey gönderilmez);
/// Grep/Glob/WebSearch/WebFetch ve diğer araçlar için hedef YOK. Anahtar kapalıyken hedef hiç hesaplanmaz.
/// `--dry-run`: ağa bağlanmadan süzülmüş yükü stdout'a yazar (testler bunu çalıştırır).
/// `decide` (ofisten cevapla) ayrı bir betiktir ve yalnızca config.json `controlEnabled: true` iken çalışır; araç girdisi özetini
/// yalnızca `/v1/decision` gövdesinde (Adalmon belleği) taşır, olay akışına (forward) ASLA.
enum AgentPluginScripts {
    /// Birincil betik: /usr/bin/python3 (3.9 uyumlu, yalnızca standart kitaplık). Hata = sessiz çıkış (exit 0).
    static let python = #"""
    #!/usr/bin/python3
    # Adalmon "Claude ajanları": Claude Code hook olaylarını yerel Adalmon dinleyicisine iletir.
    # GİZLİLİK: yalnızca aşağıdaki izinli alanlar iletilir (oturum adı session_title dahil); istem, araç girdisi/çıktısı,
    # yanıt metni ve transkript ASLA. İsteğe bağlı `target` (config.json showTargets=true): yalnızca dosya adı / komut adı.
    import json
    import os
    import re
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


    FILE_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit", "Read")
    COMMAND_PREFIXES = ("sudo", "env", "time", "nohup", "nice", "command", "exec", "builtin", "doas")
    SAFE_TOKEN = re.compile(r"^[A-Za-z0-9_.+=:/@%,-]+$")
    ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
    COMMAND_NAME = re.compile(r"^[A-Za-z0-9_.+-]{1,24}$")


    def show_targets():
        # Yalnızca config.json'daki showTargets === true; okunamazsa kapalı.
        try:
            with open(CONFIG, "r") as handle:
                return json.load(handle).get("showTargets") is True
        except Exception:
            return False


    def file_target(value):
        # Dosya yolunun son bileşeni; kontrol karakterleri atılır, en çok 40 karakter.
        if not isinstance(value, str):
            return None
        name = os.path.basename(value.rstrip("/"))
        name = "".join(c for c in name if not (ord(c) < 32 or 0x7F <= ord(c) <= 0x9F or 0xD800 <= ord(c) <= 0xDFFF)).strip()
        return name[:40] if name else None


    def command_target(value):
        # Komutun ilk gerçek kelimesi; emin olunamıyorsa (tırnak, yol, özel karakter, bayraklı önek) None.
        if not isinstance(value, str):
            return None
        tokens = value[:300].split()
        index = 0
        while index < len(tokens):
            token = tokens[index]
            if not SAFE_TOKEN.match(token):
                return None
            if "=" in token:
                if not ASSIGNMENT.match(token):
                    return None
                index += 1
                continue
            if token in COMMAND_PREFIXES:
                index += 1
                if index < len(tokens) and tokens[index].startswith("-"):
                    return None
                continue
            return token if COMMAND_NAME.match(token) else None
        return None


    def tool_target(data):
        if data.get("hook_event_name") != "PreToolUse":
            return None
        tool = data.get("tool_name")
        if tool not in FILE_TOOLS and tool != "Bash":
            return None
        if not show_targets():
            return None
        tool_input = data.get("tool_input")
        if not isinstance(tool_input, dict):
            return None
        if tool == "Bash":
            return command_target(tool_input.get("command"))
        return file_target(tool_input.get("file_path") or tool_input.get("notebook_path"))


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


    HASH_EVENTS = ("PostToolUse", "PostToolUseFailure", "PermissionDenied")


    def control_enabled():
        # Yalnızca config.json'daki controlEnabled === true ("Ofisten cevapla" açık); okunamazsa kapalı.
        try:
            with open(CONFIG, "r") as handle:
                return json.load(handle).get("controlEnabled") is True
        except Exception:
            return False


    def input_digest(data):
        # Araç girdisinin KISA ÖZETİ (SHA-256'nın ilk 16 hex'i); içerik değil. Yalnızca bekleyen ofis kararını araç sonucuyla eşlemek için.
        if data.get("hook_event_name") not in HASH_EVENTS:
            return None
        tool_input = data.get("tool_input")
        if not isinstance(tool_input, dict):
            return None
        try:
            import hashlib
            text = json.dumps(tool_input, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
            return hashlib.sha256(text.encode("ascii")).hexdigest()[:16]
        except Exception:
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
        # prompt_id ve input_hash YALNIZCA "Ofisten cevapla" açıkken (ve yalnızca araç sonuç olaylarında) gönderilir.
        if data.get("hook_event_name") in HASH_EVENTS and control_enabled():
            put("prompt_id", data.get("prompt_id"))
            digest = input_digest(data)
            if digest:
                out["input_hash"] = digest
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
        target = tool_target(data)
        if target:
            out["target"] = target
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
    # İsteğe bağlı `target` (config.json showTargets=true): yalnızca dosya adı / komut adı.
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
    # Hedef (yalnızca PreToolUse + config.json'da "showTargets": true): dosya adı (Edit/Write/MultiEdit/NotebookEdit/Read) ya da Bash komutunun
    # ilk gerçek kelimesi. Emin olunamıyorsa (tırnak, yol, özel karakter, bayraklı önek) hiçbir şey eklenmez; değerler ASCII'ye süzülür.
    command_word() {
      CMD=$(printf '%s' "$1" | /usr/bin/head -c 300)
      set -f; set -- $CMD; set +f
      while [ $# -gt 0 ]; do
        TOK=$1
        case "$TOK" in ''|*[!A-Za-z0-9_.+=:/@%,-]*) return 1 ;; esac
        case "$TOK" in
          [A-Za-z_]*=*) shift; continue ;;
          *=*) return 1 ;;
          sudo|env|time|nohup|nice|command|exec|builtin|doas)
            shift
            case "${1:-}" in -*) return 1 ;; esac
            continue ;;
        esac
        case "$TOK" in *[!A-Za-z0-9_.+-]*) return 1 ;; esac
        [ "${#TOK}" -le 24 ] || return 1
        printf '%s' "$TOK"
        return 0
      done
      return 1
    }
    TARGET=""
    if [ "$EVENT" = "PreToolUse" ]; then
      case "$TOOL" in
        Edit|Write|MultiEdit|NotebookEdit|Read|Bash)
          if [ "$(/usr/bin/plutil -extract showTargets raw -o - "$CONFIG" 2>/dev/null)" = "true" ]; then
            if [ "$TOOL" = "Bash" ]; then
              TARGET=$(command_word "$(get tool_input.command)")
            else
              TPATH=$(get tool_input.file_path)
              [ -n "$TPATH" ] || TPATH=$(get tool_input.notebook_path)
              TARGET=$(/usr/bin/basename "${TPATH:-/}" 2>/dev/null | /usr/bin/tr -cd 'A-Za-z0-9._+@ -' | /usr/bin/cut -c1-40)
              [ "$TARGET" != "/" ] || TARGET=""
            fi
          fi ;;
      esac
    fi
    if [ -n "$TARGET" ]; then BODY="$BODY$SEP\"target\":\"$TARGET\""; SEP=","; fi
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

    /// Ofisten cevaplama betiği (OFFICE-CTRL-01, yalnızca Python): PermissionRequest hook'u. Ayrıntı betiğin başlık yorumunda.
    static let decide = #"""
    #!/usr/bin/python3
    # Adalmon "Ofisten cevapla" (OFFICE-CTRL-01): Claude Code PermissionRequest hook'u (izinler VE AskUserQuestion).
    # Kapalıyken (config.json controlEnabled !== true) ağa bağlanmadan, çıktısız çıkar. Açıkken isteği 127.0.0.1'deki Adalmon'a yollar
    # ve kullanıcının tıklamasını TUTULAN bağlantıdan bekler; terminaldeki diyalog bu sırada paralel çalışır. Sonucu, kendi girdisine
    # karşı doğrulayarak hook çıktısına çevirir. Her hata/zaman aşımı/geçersiz karar = çıktısız exit 0 (normal terminal diyaloğu).
    # GİZLİLİK: araç girdisi özeti ve soru metni YALNIZCA /v1/decision gövdesinde gider (Adalmon belleği); olay akışına girmez.
    # `--dry-run` ağa bağlanmaz: istek gövdesini yazar; `--verdict '<json>'` ile verilen kararın hook çıktısını yazar.
    import copy
    import json
    import os
    import sys
    import time

    CONFIG = os.environ.get("ADALMON_AGENTS_CONFIG") or os.path.expanduser(
        "~/Library/Application Support/Adalmon/ClaudePlugin/config.json")
    MAX_HOLD = 590.0
    MODES = ("default", "acceptEdits", "plan")
    DESTINATIONS = {"user": "userSettings", "session": "session"}
    DENY_MESSAGE = "Kullanıcı Adalmon ofisinden reddetti."
    ID_MAX = 200
    LABEL_MAX = 200
    QUESTION_MAX = 500
    DESCRIPTION_MAX = 300
    HEADER_MAX = 60
    PREVIEW_MAX = 1500


    def clean(value, limit, multiline=False):
        # Kontrol karakterleri atılır (çok satırda \n ve \t kalır), uçlar kırpılır, kısaltılır. Adalmon aynı süzmeyi uygular.
        if not isinstance(value, str):
            return None
        kept = []
        for c in value:
            o = ord(c)
            if o < 32 or 0x7F <= o <= 0x9F:
                if multiline and c in "\n\t":
                    kept.append(c)
            elif 0xD800 <= o <= 0xDFFF:
                continue
            else:
                kept.append(c)
        text = "".join(kept).strip()
        return text[:limit] if text else None


    def load_config():
        try:
            with open(CONFIG, "r") as handle:
                config = json.load(handle)
        except Exception:
            return None
        if not isinstance(config, dict) or config.get("controlEnabled") is not True:
            return None
        port = config.get("port")
        token = config.get("token")
        if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port < 65536:
            return None
        if not isinstance(token, str) or not token:
            return None
        hold = config.get("holdSeconds")
        if isinstance(hold, bool) or not isinstance(hold, (int, float)) or hold <= 0:
            hold = MAX_HOLD
        return {"port": port, "token": token, "hold": min(float(hold), MAX_HOLD)}


    def input_digest(tool_input):
        # forward.py ile AYNI özet (SHA-256'nın ilk 16 hex'i): araç sonuç olayıyla eşleştirme için.
        try:
            import hashlib
            text = json.dumps(tool_input, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
            return hashlib.sha256(text.encode("ascii")).hexdigest()[:16]
        except Exception:
            return None


    def preview(tool, tool_input):
        if not isinstance(tool_input, dict):
            return None
        if tool == "Bash":
            text = tool_input.get("command")
        elif tool in ("Edit", "Write", "MultiEdit", "Read", "NotebookEdit"):
            text = tool_input.get("file_path") or tool_input.get("notebook_path")
        elif tool == "WebFetch":
            text = tool_input.get("url")
        elif tool in ("Grep", "Glob"):
            text = tool_input.get("pattern")
        elif tool == "ExitPlanMode":
            text = tool_input.get("plan")
        else:
            text = None
        if not isinstance(text, str):
            try:
                text = json.dumps(tool_input, sort_keys=True, ensure_ascii=False)
            except Exception:
                return None
        return clean(text, PREVIEW_MAX, multiline=True)


    def suggestion_label(entry):
        # Yalnızca "izin ver" kuralı ve dizin eklemeleri sunulur (mod değiştirenler ve reddetme kuralları değil).
        # Etiket, kalıcı izne dönüşecek şeyin TAMAMINI göstermelidir: kural/dizin sayısı 6'yı aşıyorsa, bir kural geçersizse ya da
        # etiket süzme/200 karakter sınırı yüzünden değişiyorsa öneri hiç sunulmaz (kullanıcının görmediği kural kalıcı olmasın).
        if not isinstance(entry, dict):
            return None
        kind = entry.get("type")
        if kind == "addRules":
            rules = entry.get("rules")
            if entry.get("behavior") != "allow" or not isinstance(rules, list) or not 1 <= len(rules) <= 6:
                return None
            parts = []
            for rule in rules:
                if not isinstance(rule, dict) or not isinstance(rule.get("toolName"), str) or not rule["toolName"]:
                    return None
                content = rule.get("ruleContent")
                parts.append(rule["toolName"] + ("(" + content + ")" if isinstance(content, str) and content else ""))
            full = ", ".join(parts)
        elif kind == "addDirectories":
            directories = entry.get("directories")
            if not isinstance(directories, list) or not 1 <= len(directories) <= 6:
                return None
            if any(not isinstance(d, str) or not d for d in directories):
                return None
            full = "Dizin: " + ", ".join(directories)
        else:
            return None
        label = clean(full, LABEL_MAX)
        return label if label == full else None


    def parse_questions(tool_input):
        # AskUserQuestion girdisi: her soru ve seçenek geçerli olmalı; bir tanesi bozuksa None (terminal yanıtlasın).
        if not isinstance(tool_input, dict) or not isinstance(tool_input.get("questions"), list):
            return None
        questions = tool_input["questions"]
        if not 1 <= len(questions) <= 4:
            return None
        parsed = []
        for item in questions:
            if not isinstance(item, dict):
                return None
            text = clean(item.get("question"), QUESTION_MAX)
            options = item.get("options")
            if text is None or not isinstance(options, list) or not 1 <= len(options) <= 8:
                return None
            labels = []
            for option in options:
                label = clean(option.get("label") if isinstance(option, dict) else None, LABEL_MAX)
                if label is None:
                    return None
                labels.append(label)
            # Yinelenen etiket (ya da aynı soru metni) cevap anahtarını belirsiz kılar: ofise sunulmaz, terminal yanıtlar.
            if len(set(labels)) != len(labels) or text in [p["text"] for p in parsed]:
                return None
            parsed.append({"raw": item, "text": text, "labels": labels, "multi": item.get("multiSelect") is True})
        return parsed


    def build_request(data, hold):
        tool = clean(data.get("tool_name"), ID_MAX)
        session = clean(data.get("session_id"), ID_MAX)
        if tool is None or session is None:
            return None
        tool_input = data.get("tool_input")
        request = {"session_id": session, "tool_name": tool, "hold": hold, "ts": time.time()}
        for key in ("agent_id", "agent_type", "permission_mode", "prompt_id"):
            value = clean(data.get(key), ID_MAX)
            if value is not None:
                request[key] = value
        cwd = data.get("cwd")
        if isinstance(cwd, str) and cwd.strip():
            project = clean(os.path.basename(cwd.rstrip("/")), ID_MAX)
            if project is not None:
                request["project"] = project
        if isinstance(tool_input, dict):
            digest = input_digest(tool_input)
            if digest:
                request["input_hash"] = digest
        if tool == "AskUserQuestion":
            parsed = parse_questions(tool_input)
            if parsed is None:
                return None
            request["kind"] = "question"
            request["questions"] = [{
                "question": q["text"],
                "header": clean(q["raw"].get("header"), HEADER_MAX),
                "multiSelect": q["multi"],
                "options": [{"label": label, "description": clean(option.get("description"), DESCRIPTION_MAX)}
                            for label, option in zip(q["labels"], q["raw"]["options"])],
            } for q in parsed]
        else:
            request["kind"] = "permission"
            text = preview(tool, tool_input)
            if text:
                request["preview"] = text
            suggestions = data.get("permission_suggestions")
            offered = []
            if isinstance(suggestions, list):
                for index, entry in enumerate(suggestions[:50]):
                    label = suggestion_label(entry)
                    if label is not None and len(offered) < 6:
                        offered.append({"index": index, "label": label})
            if offered:
                request["suggestions"] = offered
        return request


    def build_answers(tool_input, answers):
        # Her soru için cevap geçerli etiketlerden oluşmalı; tek seçimde tam bir etiket, çoklu seçimde en az bir. Çıktı: özgün soru metni
        # → özgün etiket(ler) (", " ile birleşik). Eksik/fazla/bilinmeyen herhangi bir şey = None.
        parsed = parse_questions(tool_input)
        if parsed is None or not isinstance(answers, dict) or len(answers) != len(parsed):
            return None
        result = {}
        for q in parsed:
            chosen = answers.get(q["text"])
            if isinstance(chosen, str):
                chosen = [chosen]
            if not isinstance(chosen, list) or not chosen or len(set(chosen)) != len(chosen):
                return None
            if not q["multi"] and len(chosen) != 1:
                return None
            if any(not isinstance(label, str) or label not in q["labels"] for label in chosen):
                return None
            originals = [option["label"] for option in q["raw"]["options"]]
            ordered = [originals[i] for i, label in enumerate(q["labels"]) if label in chosen]
            result[q["raw"]["question"]] = ", ".join(ordered)
        return result


    def wrap(decision):
        return {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": decision}}


    def hook_output(data, verdict):
        # Karar → hook çıktısı. Doğrulanamayan her şey None (çıktısız çıkış).
        if not isinstance(verdict, dict):
            return None
        kind = verdict.get("verdict")
        tool = data.get("tool_name")
        tool_input = data.get("tool_input")
        if tool == "AskUserQuestion":
            if kind != "answer":
                return None
            answers = build_answers(tool_input, verdict.get("answers"))
            if answers is None:
                return None
            updated = dict(tool_input)
            updated["answers"] = answers
            return wrap({"behavior": "allow", "updatedInput": updated})
        if kind == "deny":
            return wrap({"behavior": "deny", "message": DENY_MESSAGE})
        if kind != "allow":
            return None
        permissions = []
        index = verdict.get("suggestion")
        if index is not None:
            suggestions = data.get("permission_suggestions")
            if isinstance(index, bool) or not isinstance(index, int) or not isinstance(suggestions, list) or not 0 <= index < len(suggestions):
                return None
            if suggestion_label(suggestions[index]) is None:
                return None
            destination = DESTINATIONS.get(verdict.get("scope"))
            if destination is None:
                return None
            entry = copy.deepcopy(suggestions[index])
            entry["destination"] = destination
            permissions.append(entry)
        mode = verdict.get("mode")
        if mode is not None:
            if mode not in MODES:  # bypassPermissions (ve auto/dontAsk) asla
                return None
            permissions.append({"type": "setMode", "mode": mode, "destination": "session"})
        decision = {"behavior": "allow"}
        if permissions:
            decision["updatedPermissions"] = permissions
        if tool == "ExitPlanMode" and isinstance(tool_input, dict):
            decision["updatedInput"] = tool_input
        return wrap(decision)


    def emit(value):
        sys.stdout.write(json.dumps(value, sort_keys=True))
        sys.stdout.flush()


    def main():
        raw = sys.stdin.read(4000000)
        config = load_config()
        if config is None:
            return 0
        try:
            data = json.loads(raw)
        except Exception:
            return 0
        if not isinstance(data, dict) or data.get("hook_event_name") != "PermissionRequest":
            return 0
        if data.get("permission_mode") == "bypassPermissions":
            return 0
        request = build_request(data, config["hold"])
        if request is None:
            return 0
        if "--dry-run" in sys.argv:
            if "--verdict" in sys.argv:
                try:
                    verdict = json.loads(sys.argv[sys.argv.index("--verdict") + 1])
                except Exception:
                    return 0
                output = hook_output(data, verdict)
                if output is not None:
                    emit(output)
            else:
                request.pop("ts", None)
                emit(request)
            return 0
        try:
            import http.client
            connection = http.client.HTTPConnection("127.0.0.1", config["port"], timeout=config["hold"])
            connection.request("POST", "/v1/decision", body=json.dumps(request).encode("utf-8"), headers={
                "Content-Type": "application/json",
                "X-Adalmon-Token": config["token"],
            })
            response = connection.getresponse()
            body = response.read(65536)
            connection.close()
            if response.status != 200:
                return 0
            output = hook_output(data, json.loads(body.decode("utf-8")))
        except Exception:
            return 0  # Adalmon kapalı/kapattı/zaman aşımı: terminal diyaloğu karar versin.
        if output is not None:
            emit(output)
        return 0


    if __name__ == "__main__":
        try:
            main()
        except BaseException:
            pass
        sys.exit(0)
    """#
}
