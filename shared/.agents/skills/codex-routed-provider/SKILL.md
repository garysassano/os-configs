---
name: codex-routed-provider
description: Run Codex CLI non-interactively against a non-OpenAI model routed through the opencodex proxy (deepseek-v4-flash, opencode-go/Zen, GLM, Kimi, Qwen…), with write permissions and token/cache measurement. Use when asked to run codex/codex exec on DeepSeek or any routed provider, to add a provider to opencodex, or when a codex run fails with revoked-token, "unknown provider", "model metadata not found", or "model is not supported when using Codex with a ChatGPT account" (the misleading symptom of Codex not being pointed at the proxy, even while `ocx status` reports the proxy healthy).
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
Redirect stdin from `/dev/null`: `codex exec` reads stdin and appends it to the prompt as a `<stdin>` block, so with stdin still attached — which it is under any non-tty shell, including background dispatch — it blocks forever waiting for EOF, printing only `Reading additional input from stdin...` and never issuing a model request. It looks like a wedged model; it is not.

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

### Restarting can leave the proxy down — always confirm it came back

`ocx restart` fails outright against a proxy started by an older build: `❌ The running proxy predates process-bound restart support; no unsafe fallback was attempted.` It then tells you to run `ocx stop` and `ocx start` separately. That sequence has a trap: **`ocx start` runs in the foreground and does not return**, so under any tool with a timeout it gets killed or backgrounded, and if only the `stop` half landed the proxy is now **down**. Every routed request fails, including the user's own interactive Codex sessions — not just your delegation.

So never leave a stop/start half-finished, and never assume it worked:

```bash
ocx stop
ocx start &          # it does not return; background it deliberately
ocx status | head -3 # ✅ Proxy: running (PID …) + Health: … ok (live)
```

The port changes on every restart and `~/.codex/config.toml` is rewritten to match — re-read `~/.opencodex/runtime-port.json` afterwards rather than reusing the old port. And restarting is rarely the fix you want in the first place: it does **not** reset a provider's usage quota, and it will not make an exhausted account work.

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

## The proxy can be healthy while nothing routes

The most confusing failure: the proxy is up, the provider is configured, a direct `curl` to the proxy works — and every `codex exec -m <provider>/<model>` still fails with

```
The '<provider>/<model>' model is not supported when using Codex with a ChatGPT account.
```

That is not an auth or availability problem. Codex never contacted the proxy: `openai_base_url` is missing from `~/.codex/config.toml`, so the request went to the real OpenAI endpoint, which does not know the namespaced name.

**`ocx status` does not detect this.** It reports the proxy and will happily print `✅ Proxy: running / Health: ok` while nothing routes. Two checks discriminate:

```bash
ocx doctor | grep -A2 'Codex restart safety'    # routing=native  ← broken; want routing=opencodex-local
grep -c openai_base_url ~/.codex/config.toml    # 0  ← broken; want 1
```

Observed cause (2026-08-22): a mise-managed `codex` upgrade replaced the shimmed binary, destroying both the opencodex shim and its `codex.opencodex-real` backup (`ocx codex-shim status` reports "wrapper present but not an opencodex shim"), after which routing was left native while the proxy kept running. Any package-manager reinstall of `codex` can do this.

Fix with `ocx restore back`, which re-points Codex at the running proxy. It rewrites the user's global config, so back it up first and report the diff:

```bash
cp -p ~/.codex/config.toml ~/.codex/config.toml.bak-$(date +%Y%m%d-%H%M%S)
ocx restore back
```

It adds exactly two top-level lines (plus a comment) and removes nothing:

```toml
model_catalog_json = "/home/user/.codex/opencodex-catalog.json"
# Auto-injected by opencodex
openai_base_url = "http://127.0.0.1:<port>/v1"
```

Undo is `ocx restore`. Afterwards `ocx doctor` may still warn `AT RISK after restart (background service files are stale; run 'ocx service repair')` — that is the leftover broken shim, and routing will not survive a restart until it is repaired.

### Only one of those two lines is load-bearing

`openai_base_url` does the routing. `model_catalog_json` only supplies model metadata: without it a routed run still works and merely warns `Model metadata for <model> not found`. That warning is itself an artifact of the hijack — Codex believes the model belongs to the built-in `openai` provider and fails to find it in that catalog.

### The scoped alternative

Codex supports proper per-provider routing, so the global hijack is a choice, not a requirement (verified on codex-cli 0.149.0; passes `--strict-config`):

```toml
[model_providers.ocx]
name = "opencodex"
base_url = "http://127.0.0.1:10100/v1"
wire_api = "responses"
env_key = "OCX_PROBE_KEY"
```

Select it per call with `-c model_provider=ocx`, or once via `$CODEX_HOME/<name>.config.toml` plus `-p <name>`. The header then reads `provider: ocx`, native models are untouched, and no metadata warning appears.

opencodex prefers the hijack because it makes *plain* `codex` — interactive, TUI model picker included — route everything with no flags. Tradeoffs: the hijack puts the proxy in the path for every request including native OpenAI models, while the scoped form costs a flag or profile per invocation. **Neither fixes port staleness** — both hardcode the port, which changes on every `ocx restart`; the difference is that `ocx` rewrites its own injected line and would overwrite or ignore a hand-rolled `model_providers` entry. Use the scoped form in a throwaway `CODEX_HOME`, not in a config `ocx` manages.

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
