# OFFICE-CTRL-01 plan: answer Claude Code prompts from the agent office

Date: 2026-11-12. Local Claude Code: 2.1.322 (`claude --version`). Read-only plan, no code changed.

## 1. Goal and constraints

Goal: from the agent office (macOS window/pano card), the user can (a) send a message to a running Claude Code session, (b) answer its permission prompts, (c) answer its AskUserQuestion prompts, and (d) switch its permission mode.

Constraints:
- Use official, documented mechanisms only.
- Keep the existing pipeline: plugin `adalmon-agents` hooks POST to a 127.0.0.1 listener with token, Host and Origin checks.
- Privacy: only event, session, agent and tool names, model and project are sent. Never prompts, commands or file contents.
- `tasks.json` says the task is "konuşulmadan kodlanmayacak" (no code before it is discussed), and the security model needs the user's approval.
- Do not drive the UI or send keys to other apps. Do not break the existing setup.
- Battery: idle CPU below about 1%.
- Tests must not overwrite the real `config.json` or `~/.claude/settings.json`.

## 2. Feasibility matrix (official docs, verified 2026-11-12)

| Feature | Official mechanism | Works with an interactive TUI session? | Limitations |
|---|---|---|---|
| Answer permission prompt (Allow/Deny) | Synchronous `PermissionRequest` hook returns `hookSpecificOutput.decision.behavior` = `allow`/`deny` (+`message`, `interrupt` on deny). Exit 2 is NOT honored for this event. | Yes (it is a hook) | **Unknown (spike #1):** is the terminal dialog shown while the hook is still running, or only after it returns? Is the hook cancelled if the user answers in the terminal? The docs only say "whichever decides first" for `--permission-prompt-tool`/`canUseTool` hosts. There is no `tool_use_id`, so correlate by session/agent. Deny/ask rules are still evaluated after an allow. |
| "Always allow" | Same hook, `decision.updatedPermissions` entries (`addRules`, ...) with `destination` `session`/`localSettings`/`projectSettings`/`userSettings`. The input carries `permission_suggestions`. | Yes | The suggestions "aren't an exact list of the dialog's options". Writing `localSettings`/`userSettings` changes the user's files (needs a product decision). |
| Switch permission mode | Only as `updatedPermissions: [{type:"setMode", mode:..., destination:"session"}]` attached to an **allow** on a pending PermissionRequest. Modes: `default/manual, auto, acceptEdits, dontAsk, bypassPermissions, plan`. | Partly: only at the moment a permission prompt is pending | No standalone "change mode now" API exists. `bypassPermissions` works only if it was available at launch. Never offer bypass. A spike must check whether `plan` → `acceptEdits` works this way. |
| Plan approval (ExitPlanMode "mode window") | PreToolUse matcher list includes `ExitPlanMode`. PermissionRequest "matches on tool name, same values as PreToolUse". | Assumption: yes (spike #2) | Not explicitly documented that the plan-approval dialog fires PermissionRequest. If it does, Allow + `setMode acceptEdits` is "approve plan and auto-accept edits". |
| Answer AskUserQuestion | Synchronous `PreToolUse` hook, matcher `AskUserQuestion`, returns `permissionDecision:"allow"` + `updatedInput` = original `questions` + `answers` {question text → chosen label; multi-select = labels joined by commas}. | Yes, but it is **always blocking**: PreToolUse runs before the tool, so the terminal question UI appears only after the hook returns with no decision | Needs the question text and options, which are Claude-authored content and conflict with the privacy rule, so this needs an explicit opt-in. Hold time must be bounded (fall open to the terminal). |
| Inject a user message | **Channels** (research preview): an MCP stdio server with `capabilities.experimental['claude/channel']` emits `notifications/claude/channel` {content, meta}. A custom channel is not on the allowlist, so every session must be launched with `claude --dangerously-load-development-channels plugin:<name>@<mkt>` (shows a full-screen warning each launch). | Yes, but only sessions started with that flag; the flag is ignored in `-p`/SDK | Research preview, and the contract may change. Requires claude.ai or Console auth. Blocked by Team/Enterprise policy unless `channelsEnabled`. Pre-built channels use Bun; a hand-written Python stdio JSON-RPC server is an **assumption** (docs: "only hard requirement is the MCP SDK"). A server negotiating MCP revision 2026-07-28 won't register. The message arrives as a `<channel>` tag, not a real user turn. |
| Permission relay via channel | `claude/channel/permission` capability. Claude Code sends `notifications/claude/channel/permission_request` {request_id, tool_name, description, input_preview}. The verdict is `notifications/claude/channel/permission` {request_id, behavior}. | Yes, and **parallel with the terminal dialog** ("whichever answer arrives first") | Same launch-flag cost as above. Covers Bash/Write/Edit-style tool approvals only (AskUserQuestion and plan approval are not mentioned). No "always", no mode switch. |
| Remote Control | claude.ai/code or the mobile app drives the local session through the Anthropic API (outbound only, no inbound port). | Yes, but only from Anthropic clients | **No local API.** Using it from Adalmon would need undocumented endpoints, so it is rejected. |
| `claude -p --resume <id> "msg"` | Headless resume | **No** for a live TUI session | Starts a second process on the same conversation. Concurrent-writer behaviour is undocumented (assumption: a fork or conflict), so it is rejected for live sessions. Fine only for sessions that are not running. |
| AskUserQuestion `defer` | PreToolUse `"defer"` → run ends `stop_reason:"tool_deferred"`, resume with `-p --resume` | No (headless only) | Not for interactive sessions. |
| asyncRewake hook | Background hook; exit 2 "wakes Claude immediately even when idle" | Technically | Bound to one event firing and its timeout. Using it as a mailbox is a hack, so it is rejected. |
| MCP Elicitation hook | `Elicitation` hook answers MCP-server forms (`action` accept/decline/cancel + `content`) | Yes | Only for MCP-server forms, not AskUserQuestion or permissions. Out of scope. |
| Keystroke injection / AppleScript into the terminal | none (undocumented) | — | Rejected: undocumented, and violates "do not send keys to other apps". |

Notification hook: `permission_prompt` notifications fire only after about 6 s of waiting. Adalmon already uses this for status, so it is not a control path.

## 3. Recommended MVP scope

MVP = **permission prompts (Allow / Deny / Always-for-session / Allow + switch mode) + AskUserQuestion answers**, via synchronous hooks in the existing plugin, **off by default**, macOS app only.

Not in the MVP:
- **Message box.** The only official path is dev-channels with a launch flag and a warning screen every time. Show it as Phase 2 / "ask the user". Until then the card can show a disabled "Mesaj gönder" with the reason, or nothing.
- Mode switching outside a pending prompt (impossible).
- Browser/web view control (read-only stays).
- Remote/LAN.

Phase 0 (spike, before any UI): verify on Claude Code 2.1.322 with a throwaway hook in a temp project (not in the user's settings):
1. While a sync PermissionRequest hook sleeps 20 s, is the terminal dialog visible? If the user answers in the terminal, is the hook killed or is its later output ignored?
2. Does ExitPlanMode plan approval fire PermissionRequest? Does `setMode acceptEdits` apply?
3. Does PermissionRequest/PreToolUse input carry `agent_id` for subagent calls, and `permission_mode`?
4. In `auto`/`acceptEdits` modes, which prompts still reach PermissionRequest?
5. AskUserQuestion multi-question + multiSelect answer format accepted end-to-end.

The branch from spike #1 decides the hold policy:
- **Parallel** (dialog shown while the hook runs): hold until answered, up to a cap (e.g. 10 min; default hook timeout is 600 s). If the user answers in the terminal, the hook dies, the connection closes, and Adalmon drops the card.
- **Blocking** (dialog only after the hook returns): hold only for sessions where the user turned on "Ofisten cevapla". Use a short cap (e.g. 120 s) with a visible countdown on the card, then fall open to the terminal dialog. AskUserQuestion is always in this branch.

## 4. Architecture and data flow

```
Claude Code ──sync hook (PermissionRequest | PreToolUse[AskUserQuestion])──▶ decide.py (new, python only)
   decide.py: read stdin → config.json: controlEnabled? session opted in? else exit 0 (no network)
            → POST /v1/decision (token, Host 127.0.0.1:port, no Origin) body: {kind, session_id, agent_id,
              tool_name, permission_mode, project, [preview fields if contentOptIn], suggestions(summarised),
              questions(if AskUserQuestion & contentOptIn)}  ── connection HELD
Adalmon AgentEventServer: parse → PendingDecisionStore (memory only) → office card shows request
   user clicks Allow/Deny/Always/answer → reply written on the SAME held connection: {"verdict":"allow",
     "suggestion":0, "mode":"acceptEdits", "answers":{...}}  (minimal verdict)
decide.py: validates verdict against its own stdin (answer labels must exist; suggestion index in range;
   mode in whitelist, never bypassPermissions) → builds hookSpecificOutput JSON → stdout → exit 0
Any error / timeout / Adalmon closed / malformed verdict → exit 0, no output → normal terminal dialog.
```

Security properties:
- **There is no "approve" HTTP route.** A token holder can only *create* a pending prompt; approval happens only by a click in the Adalmon process. A local attacker with the token can at most show a fake card. Mitigation: show session title, project and pid, and only accept requests whose `session_id` is a known live session.
- Local-only listener (existing), constant-time token check, and the same Host/Origin checks as `/v1/limits` (`AgentHTTPParser.swift:44-50`).
- Opt-in in three layers: a global "Ofisten izin/soru cevapla" setting (off), per-session "Ofisten cevapla" (if spike #1 says blocking), and a content opt-in (see the questions).
- Audit log (JSONL, Application Support, rotated): time, session_id, project, tool_name, kind, verdict, mode, "always" yes/no. **No content.**
- Hook never uses `onFailure:"block"` (that would deny on failure). It fails open.
- Separate cap for held connections (e.g. 8) so the event forwarder (`maxConnections = 16`, `AgentEventServer.swift:16`) is never starved.

Privacy: preview fields (`tool_input` summary, question text/options, `permission_suggestions` rule text) travel only in `/v1/decision`.
- They live only in `PendingDecisionStore` memory, never in `AgentEvent`, `/v1/state`, SSE, the web snapshot or logs.
- They are truncated in the hook (e.g. 2 KB per field, body under the 16 KB `maxBody`).
- Without the content opt-in the card shows only the tool name, project and file/command name (the existing `showTargets` rules), and AskUserQuestion is not offered. The terminal still handles it.

## 5. Files to touch (order: shared interfaces first; disjoint pieces for separate agents)

**Piece A — model and protocol (first, shared):**
- NEW `Sources/App/Agents/AgentDecision.swift`: `PendingDecision` (id, kind permission/question, sessionID, agentID, toolName, project, permissionMode, preview?, suggestions[{index,label}], questions[{question, header, options[label,description], multiSelect}], receivedAt, deadline) and `DecisionVerdict` (allow/deny, suggestionIndex?, mode?, answers?, message?) plus JSON encode/decode with strict limits.
- NEW `Sources/App/Agents/AgentDecisionParser.swift`: `POST /v1/decision` parser (reuse the `AgentHTTPParser` header logic; Host/Origin/token like limits; its own key whitelist; 16 KB cap).
- NEW `Sources/App/Agents/PendingDecisionStore.swift` (@MainActor, @Observable): add/resolve/cancel; clear by (session, agent) on PostToolUse/PostToolUseFailure/Stop/SessionEnd from `AgentState` events; audit log writer (JSONL, metadata only).

**Piece B — listener (after A):**
- `Sources/App/Agents/AgentEventServer.swift`: route `/v1/decision` (today `receive` at :188 dispatches only `AgentHTTPParser`). Keep that connection out of the 5 s timeout (:182, the same pattern as the `sseClients` exemption). Give held connections their own cap. Keep a `pending: [UUID: NWConnection]` map. `resolve(id, verdict)` writes `HTTP/1.1 200` + JSON and closes. When the connection is closed, call `store.cancel(id)`.
- `Sources/App/Agents/AgentHTTPParser.swift`: only if the path check (:37-38) must let `/v1/decision` through to the new parser. Prefer peeking at the request line in the server instead.

**Piece C — plugin (independent of B, after A's JSON contract):**
- `Sources/App/Agents/AgentPluginScripts.swift`: add `static let decide` (Python 3.9, stdlib only).
  - Order: read config → gate (fail open) → build request → hold POST with socket timeout = hold cap → validate verdict against stdin → print `hookSpecificOutput`.
  - PermissionRequest: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":..., "updatedPermissions":[echoed suggestion and/or {"type":"setMode","mode":m,"destination":"session"}], "message":...}}}`.
  - AskUserQuestion: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"questions":<stdin questions>,"answers":{...}}}}`.
  - `--dry-run` mode for tests. No shell fallback: on machines without Python the feature is off and the UI says why.
- `Sources/App/Agents/AgentPluginGenerator.swift`:
  - `hooksJSON` (:82-88): add sync entries `PermissionRequest` (no matcher) and `PreToolUse` with matcher `^AskUserQuestion$`, running `decide.py`, no `async`, `timeout` = hold cap + 5.
  - Keep the existing async forward entries unchanged.
  - Write `scripts/decide.py`.
  - Bump `version` (:14) to 1.4.0 and include `decide` in `scriptsDigest` (:16-19).
  - `config.json` new keys: `controlEnabled` (bool), `controlContent` (bool), `controlSessions` ([session_id], only if the per-session gate is chosen), `holdSeconds`. Use setter helpers like `setShowTargets` (:114).
- `Sources/App/Agents/AgentPluginInstaller.swift`: probably nothing. Only touch it if a version bump needs a reinstall step (check during the work).

**Piece D — service and settings (after A and B):**
- `Sources/App/Agents/AgentService.swift`: own `PendingDecisionStore`, wire it into server start (`startListening` :108), forward resolve calls, add `setControlEnabled/setControlContent`. Wire session-end cleanup from the monitor model.
- `Sources/App/Agents/AgentMonitorModel.swift`: expose pending decisions per session to the UI. A session with a pending decision counts as "needs attention" (the existing `SessionDormancy.needsAttention` path, :84).
- Settings pane for Claude agents (find the file with `grep -rn "showTargets" Sources/App/UI`): toggles plus warning text plus "Denetim kaydını göster".

**Piece E — office UI (after A and D):**
- `Sources/App/Office/OfficeV3Logic.swift`: `OfficeDetailCard` (:203) gets `pendingDecisionID`/summary (Equatable, no content needed for diffing).
- `Sources/App/UI/MainWindow/AgentOffice/OfficeSceneContainer.swift`: `OfficeCardView` (:113) shows an "İzin isteği" section with tool, project, preview (if allowed) and buttons **İzin ver / Reddet / Bu oturumda hep izin ver** plus a mode menu (Varsayılan / Düzenlemeleri kabul et / Plan; never bypass), and a countdown when holding. For a question it shows options (radio or multi-select checkboxes) and **Cevapla**.
  - The waiting character's click already selects the member (`OfficeScene.setSelectedMember` :578). Auto-open the card when a decision arrives only if the office window is key. Otherwise use a balloon or badge.
- The web view (`AgentWebSnapshot.swift`, `AgentWebRouter.swift`) is **not touched**. Add a test that its JSON has no decision content.

**Piece F — tests (each piece ships its tests):** `Tests/AgentDecisionTests.swift` (parser limits, Host/Origin/token, whitelist), `Tests/PendingDecisionStoreTests.swift` (resolve, cancel on close, clear on PostToolUse/Stop, audit log has no content keys), `Tests/AgentPluginTests.swift` (digest/version, hooksJSON has the sync entries and they are not async; decide.py `--dry-run` cases: gate off means no output; malformed verdict means no output; bad answer label means no output; `bypassPermissions` refused; AskUserQuestion output shape), and a server integration test (held connection, resolve writes JSON, timeout/close cancels) using `AgentPluginGenerator(root:)` temp dirs.

**Phase 2 (only if the user wants a message box):** NEW channel plugin `adalmon-channel` (python stdio MCP, `claude/channel` + optional `claude/channel/permission`). It connects back to Adalmon (long-poll `/v1/channel/inbox?session=` with token) instead of opening its own port. It needs a launch helper/alias (`claude --dangerously-load-development-channels plugin:adalmon-channel@adalmon-local`). It is a separate task with its own spike (Python MCP handshake, protocol revision).

## 6. Risks and assumptions

- **[Unverified, decisive]** Whether the hook blocks the terminal dialog (spike #1). If it blocks and Adalmon is open but the user is at the terminal, every prompt is delayed by the hold cap. This is why there is a per-session opt-in and a short cap.
- **[Unverified]** ExitPlanMode via PermissionRequest; `agent_id` present on PermissionRequest; behaviour in `auto` mode.
- Hook latency: an opted-out user pays only Python startup (~30-60 ms) per PermissionRequest/AskUserQuestion, not per tool call (narrow matchers). Assumption to measure.
- Fail-closed bugs: a malformed hook output on PreToolUse could deny or alter a tool call. The hook validates everything and emits nothing on doubt.
- Spoofed cards from a local process holding the token. Mitigated: no remote approve route, known-session check, card shows project/pid.
- Privacy regression: content leaking into `/v1/state`, SSE or logs. Mitigated by a separate type and grep tests.
- "Always" with non-session destinations writes the user's settings files, which conflicts with "mevcuttaki düzeni bozma" (do not break the existing setup). The default is session only.
- Plugin version bump: Claude caches plugins by version, and running sessions keep the old hooks until restart (assumption based on `AgentPluginGenerator.swift:12` comment).
- Two answerers (terminal + office): stale card. Cleared on connection close, PostToolUse or Stop.
- Battery: no timers; held connections are idle sockets; card countdown only while visible (TimelineView already used).
- Channels (Phase 2): research preview, contract may change, warning screen per launch, Python MCP server unproven.

## 7. Done when

Automated (each must exit 0 / match):
1. `xcodebuild test -scheme Adalmon -derivedDataPath /private/tmp/claude-501/adalmon-dd-ctrl -only-testing:AdalmonTests/AgentDecisionTests -only-testing:AdalmonTests/PendingDecisionStoreTests -only-testing:AdalmonTests/AgentPluginTests -only-testing:AdalmonTests/AgentHTTPParserTests -only-testing:AdalmonTests/AgentWebTests` exits 0 (scheme and target names to confirm from `project.yml`).
2. `grep -rnE '"(tool_input|questions|answers|input_preview)"' Sources/App/Agents/AgentWebSnapshot.swift Sources/App/Agents/AgentEvent.swift` finds nothing.
3. `md5 ~/Library/Application\ Support/Adalmon/ClaudePlugin/config.json ~/.claude/settings.json` is identical before and after the test run.
4. `git diff --name-only` lists only the files in section 5 (plus new test files and `project.yml` if xcodegen needs it).
5. With control disabled: `echo '{"hook_event_name":"PermissionRequest","session_id":"x","tool_name":"Bash","tool_input":{"command":"ls"}}' | ADALMON_AGENTS_CONFIG=<tmp config> python3 decide.py` prints nothing and exits 0 in under 200 ms.

Manual (task `done_when`, user sign-off): the user approves the security model, and in a real interactive session they Allow, Deny, Always and Allow + acceptEdits a prompt and answer one AskUserQuestion from the office.

## 8. Questions for the user (main session asks; recommendation first)

1. **Showing content in the card** (tool input, question text) conflicts with the current privacy rule.
   - (Rec) Off by default, separate "İçeriği göster" toggle, memory only and never logged.
   - Global on when control is on.
   - Never: tool name and file/command name only, and AskUserQuestion stays terminal-only.
2. **Who can answer:**
   - (Rec) Only the macOS app (window/pano card).
   - Also the browser view (adds a CSRF/approve-route attack surface).
3. **What "Always allow" writes:**
   - (Rec) This session only (`destination: session`).
   - The project's `.claude/settings.local.json` (persists, touches project files).
   - No "Always" button.
4. **Message box (send a message to a session):**
   - (Rec) Not now. Ship permissions and questions first.
   - Phase 2: Adalmon channel plugin, every session launched with `--dangerously-load-development-channels` (warning screen each time, research preview).
   - Never.
5. **Hold behaviour if the spike shows the hook blocks the terminal dialog:**
   - (Rec) Hold only for sessions marked "Ofisten cevapla", 120 s cap with countdown, then terminal.
   - Hold for all sessions while Adalmon is open.
   - Do not hold (permissions only if parallel).
6. **Mode switch options offered** (only together with an Allow):
   - (Rec) Default / acceptEdits / plan.
   - Also auto/dontAsk.
   - (bypassPermissions is never offered, and this is not a user option.)

## Sources
- https://code.claude.com/docs/en/hooks (PermissionRequest decision/updatedPermissions/setMode, AskUserQuestion via PreToolUse updatedInput+answers, defer, async/asyncRewake, Elicitation, timeouts 600 s, http hooks)
- https://code.claude.com/docs/en/channels-reference (channel contract, permission relay, dev flag)
- https://code.claude.com/docs/en/channels (requirements, research preview, security, enterprise controls)
- https://code.claude.com/docs/en/remote-control (Anthropic-routed, outbound only, no local API)
