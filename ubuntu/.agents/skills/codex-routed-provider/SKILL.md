---
name: codex-routed-provider
description: Run Codex CLI non-interactively against a non-OpenAI model routed through the opencodex proxy (deepseek-v4-flash, opencode-go/Zen, GLM, Kimi, Qwen…), with write permissions and token/cache measurement. Use when asked to run codex/codex exec on DeepSeek or any routed provider, to add a provider to opencodex, or when a codex run fails with revoked-token, "unknown provider", or "model metadata not found".
---

# Codex on a routed (non-OpenAI) provider

opencodex is a local proxy that translates Codex's Responses API to any provider.
Codex reaches it because `~/.codex/config.toml` sets `openai_base_url` to the proxy.
Verified working end to end on 2026-08-06 with `opencode-go/deepseek-v4-flash`.

## The invocation

```bash
timeout 1800 codex exec \
  -m opencode-go/deepseek-v4-flash \
  -s workspace-write \
  --skip-git-repo-check \
  "$(cat /path/to/prompt.txt)" \
  < /dev/null
```

`workspace-write` is enough to create, edit, and run tests in cwd — `exec` issues no approval prompts, and `--dangerously-bypass-approvals-and-sandbox` was never needed.
Redirect stdin from `/dev/null` for the same reason the `codex-kiro` skill gives: `codex exec` appends stdin to the prompt and blocks forever waiting for EOF under any non-tty shell.

Model syntax is `provider/model`.
The prefix only resolves if that provider is **configured**; otherwise it silently falls through to the default provider (`openai`) and you get a confusing ChatGPT auth error instead of a routing error.

## Adding a provider — verify on disk, then restart

Registry providers are auto-configured by name; only custom ones need `--adapter`/`--base-url`.

```bash
set -a; . ~/.reasonix/.env; set +a          # OPENCODE_GO_API_KEY lives here
ocx provider add opencode-go --api-key "$OPENCODE_GO_API_KEY" --default-model deepseek-v4-flash
jq -r '.providers | keys | join(", ")' ~/.opencodex/config.json   # ← MUST confirm here
ocx restart && ocx sync
jq -r '.providers | keys | join(", ")' ~/.opencodex/config.json   # ← and again after
```

**`ocx provider list` is not proof.** It reports live process state.
The add can report `✅` and appear in the list without ever reaching `config.json`; a subsequent `ocx restart` then reloads the older file and the provider is gone — and it can take unrelated providers with it (this silently dropped a configured `kiro` entry).
Always diff `config.json` before and after, and re-add anything that disappeared.
Credentials in `~/.opencodex/auth.json` survive this and do not need re-login.

Routing also does **not** work until you restart — the running proxy will not pick up a newly added provider, and requests fall back to `openai`.

## Port is dynamic

Not always 10100.
Read it from `ocx status` or `~/.opencodex/runtime-port.json`; it changes on every restart, and `~/.codex/config.toml` is rewritten to match.

Smoke-test routing without involving Codex — any bearer string is accepted once the target provider is configured:

```bash
P=$(jq -r .port ~/.opencodex/runtime-port.json)
curl -s -X POST localhost:$P/v1/responses -H 'content-type: application/json' \
  -H 'authorization: Bearer probe' \
  -d '{"model":"opencode-go/deepseek-v4-flash","input":"say ok","stream":false}'
```

## When Codex's own login is revoked

Codex refreshes its ChatGPT credential at startup **even when routing elsewhere**, so `refresh_token_invalidated` / "your session has ended" kills the run before any provider request is made.
The user must fix it with `codex login`.
To work around it without touching their `~/.codex`, use a throwaway home:

```bash
export CODEX_HOME=/path/to/scratch/codex-home
mkdir -p "$CODEX_HOME"
printf 'openai_base_url = "http://127.0.0.1:%s/v1"\n' "$P" > "$CODEX_HOME/config.toml"
echo "dummy-key" | codex login --with-api-key
```

Codex honours `CODEX_HOME` for config, auth, catalog, and sessions.

## Harmless noise

| Message | Meaning |
|---|---|
| `failed to connect to websocket: HTTP error: 426 Upgrade Required` | Codex tries `ws://…/v1/responses` first; the proxy is HTTP-only. It falls back silently. Appears every turn. |
| `Model metadata for <model> not found. Defaulting to fallback metadata` | Routed model is missing from `~/.codex/opencodex-catalog.json`. Run `ocx sync`. Runs fine without it. |

## Measuring tokens and cache

`~/.opencodex/usage.jsonl` holds one row per request and includes `cachedInputTokens` when the provider reports it.
Slice by epoch-ms timestamp:

```bash
jq -s --argjson s "$START_MS" --argjson e "$END_MS" \
  '[.[] | select(.timestamp>=$s and .timestamp<=$e and .provider=="opencode-go")]
   | {reqs: length, input: (map(.usage.inputTokens//0)|add),
      cached: (map(.usage.cachedInputTokens//0)|add),
      out: (map(.usage.outputTokens//0)|add)}' ~/.opencodex/usage.jsonl
```

Error rows carry no `usage` object at all, so the `//0` defaults silently absorb them — always count `status != 200` separately rather than trusting the token totals to reveal a failed run.

Measured baseline for a small multi-file edit task (3 runs, `deepseek-v4-flash`): 7–13 requests, ~95% cache-hit rate, 55–142 s wall clock.
A hit rate far below that suggests prefix instability, not a slow model.
