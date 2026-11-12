# OFFICE-CTRL-01: Phase 0 spike results

Date: 2026-11-12. Claude Code 2.1.322. Model `--model haiku`. Hooks lived only in the temp project's `.claude/settings.local.json`, which has been deleted.
Every answer below comes from INTERACTIVE TUI sessions. A Python `pty` driver sent the keystrokes and logged the screen. No print mode was used.
Timestamps such as `397.089` are the last digits of epoch `1794466397.089` (seconds). Hook log lines come from the hook process. "Dialog seen" is when the driver first saw the dialog text in the PTY output.

## 1. Sync PermissionRequest hook vs. the terminal dialog: PARALLEL

- The dialog appears while the hook is still running.
  - spike-a: hook started at `397.089`, dialog seen at `397.249`, hook slept until `417.176`.
  - spike-c: the dialog was drawn at `455.913`, before the hook process even started (`455.951`).
- **When the user answers in the terminal, the hook is not killed.** No signal reached it. Its heartbeats went on (`HB 6..20`, `403.1..417.2`) after Enter was pressed at `402.254`.
  - The tool ran right away (tool_result at `402.85`).
  - At `417.176` the hook returned `deny "SPIKE-LATE-DENY"`. That late output was ignored: it is in neither the transcript nor the screen.
  - The next turn did not wait for the orphan hook.
- **Allow without a dialog? Not quite.** The tool is allowed with no user input. The dialog is still drawn briefly, for about 0.1–0.15 s, and then closed, because it renders in parallel with the hook.
- **A hook `allow` closes a dialog that is already open.**
  - spike-b: dialog seen at `433.310`, hook allowed at `443.240`, tool ran at `443.35`. The screen shows `Allowed by PermissionRequest hook`.
  - spike-c: an immediate allow closed the dialog within about 0.1 s.
- Plan correction: §3 "the hook dies, the connection closes" is wrong. The hook lives until it returns or its `timeout` runs out. Adalmon has to drop the card some other way. One way is the next hook event for the same session or agent (PostToolUse, PostToolUseFailure, Stop, UserPromptSubmit). A late click is harmless because Claude Code ignores the output.
  - Adalmon must also close the held connection when it drops the card, so the orphan decide.py exits right away instead of lingering until the cap (battery rule).
  - Risk: with no `tool_use_id`, "next event" can misattribute when parallel tool calls run in one batch. Match on session_id + agent_id + tool_name + tool_input, plus `prompt_id`, against PostToolUse, PostToolUseFailure and PermissionDenied.

## 2. ExitPlanMode → PermissionRequest; setMode acceptEdits: YES, it works

- Hook events: `517.585 PreToolUse ExitPlanMode mode=plan`, then `517.643 PermissionRequest ExitPlanMode mode=plan`.
- The hook returned `allow` with `updatedInput` (an echo of tool_input) and `updatedPermissions:[{type:setMode, mode:acceptEdits, destination:session}]`.
- Screen: the "Ready to code? … Would you like to proceed?" dialog flashed at `517.623`. At `517.707` the status bar showed `⏵⏵ accept edits on`, followed by "User approved Claude's plan".
- After that, every hook received `mode=acceptEdits`.
- Side note: with the user's settings, plan mode switched the model to Sonnet for the planning turn, and the plan was saved under `~/.claude/plans/`.

## 3. Input fields

- `permission_mode` is present in both PermissionRequest and PreToolUse input.
- `agent_id` and `agent_type` are present for subagent calls: `PermissionRequest tool=Bash agent_id=ac271fddd8abda9f0 agent_type=general-purpose`. This was a background general-purpose agent.
- PermissionRequest keys: `cwd, effort, hook_event_name, permission_mode, permission_suggestions, prompt_id, scratchpad_dir, session_id, tool_input, tool_name, transcript_path`, plus `agent_id`/`agent_type` in a subagent. There is no `tool_use_id`.
- PreToolUse has the same keys, plus `tool_use_id` and without `permission_suggestions`.
- New and useful: `prompt_id`.

## 4. acceptEdits: which calls still prompt (tested sample, consistent with docs)

| Call | PermissionRequest fired? | Notes |
| --- | --- | --- |
| Write `a.txt` inside the project | no | |
| `touch c.txt` | no | |
| Write outside the project | yes | `sugg=[addDirectories …]` |
| Non-read-only Bash `python3 -c …` | yes | `sugg=[addRules …]` |

- Not tested here, documented elsewhere: protected paths, critical rm, and AskUserQuestion always prompt.
- Auto mode was not tested.

## 5. AskUserQuestion: both paths work

- **PreToolUse path:** a `^AskUserQuestion$` hook returned `allow` with `updatedInput` (the original questions plus `answers`). No dialog was shown and PermissionRequest did not fire.
  - The model received: `"Pick a color"="Blue", "Pick fruits"="Apple, Cherry"`. This was multiSelect, with labels joined by `", "`.
- PreToolUse is **blocking**. With a 15 s PreToolUse hook, the dialog appeared only after the hook returned (hook ended `858.433`, dialog seen `858.525`).
- **PermissionRequest also fires for AskUserQuestion**, in parallel with its dialog:
  - dialog seen at `940.360`
  - PermissionRequest hook started at `940.382`
  - after 5 s, at `945.398`, the hook returned `allow` + `updatedInput{questions, answers}`
  - the dialog closed and the model received `"Pick a shape"="Square"`
- Gap: the PermissionRequest path was tested with one single-select question in default mode only. Multi-question and multiSelect via PermissionRequest were NOT tested. The same `answers` shape is expected.

## Recommended hold strategy: the **Parallel** branch, for both permissions and AskUserQuestion

- Use a **PermissionRequest** hook for AskUserQuestion. Do not use PreToolUse: PreToolUse would block the terminal.
- Hold the connection until a click or a cap (≤ hook `timeout`, e.g. 600 s). No per-session opt-in is needed for blocking reasons.
- Close the card on the next event from the same session/agent.
- On a cap timeout, exit 0 with no output.
- decide.py's own cap must be strictly below the hook `timeout` (e.g. 590 s against 600 s), so it always exits cleanly and is never killed by the timeout. Not verified: what Claude Code does when a PermissionRequest hook hits its `timeout` while the dialog is open.

## Usage and side effects

- 6 launches: 5 prompted haiku sessions of about 1–2 min each, plus 1 no-prompt 7 s smoke test. This is within the ≤6 limit.
- The plan-mode turn ran on Sonnet because of the user's model settings.
- Left behind, because they are under `~/.claude`, which this spike may not touch:
  - transcripts in `~/.claude/projects/-private-tmp-claude-501-office-spike-5bff66-proj/`: 5 jsonl files, a subagent directory and `memory/`
  - `~/.claude/plans/write-a-2-line-plan-nifty-hammock.md`
  - a project entry in `~/.claude.json`
- The child sessions also started `/rc` remote control, because of the user setting `remoteControlAtStartup`.
