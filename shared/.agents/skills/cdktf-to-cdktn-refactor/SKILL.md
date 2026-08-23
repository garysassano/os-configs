---
name: cdktf-to-cdktn-refactor
description: Convert Projen-managed CDKTF TypeScript apps to a native, mise-managed CDK Terrain (cdktn) project on pnpm 11, TypeScript 7, ESM, Biome, and Vitest. Use when a repo has `.projenrc.ts` with `CdktfTypeScriptApp`, depends on `cdktf`/`cdktf-cli`, imports `@cdktf/provider-*` prebuilt packages, or the user asks to drop Projen from a CDKTF app or move from CDKTF to CDKTN.
---

# CDKTF to CDKTN Refactor

## Overview

Two migrations happen at once, and they are independent:

1. **Projen shell → native project shell.** Same decisions as `projen-cdk-ts-refactor`: delete generated state, keep infrastructure code, own the config files.
2. **CDKTF → CDKTN.** `cdktf` and `cdktf-cli` become `cdktn` and `cdktn-cli` (bin: `cdktn`), from the community fork at <https://github.com/open-constructs/cdk-terrain>.

Do the library swap first — it decides whether provider bindings are generated or prebuilt — then apply the project shell around it.

For a plain AWS CDK app with no Terraform in it, use `projen-cdk-ts-refactor` instead. For a fresh AWS CDK scaffold, use `cdk-scaffolding`.

## CDKTN facts that drive the migration

Verify these against the installed version before relying on them; they were confirmed against `cdktn@0.24.0`.

- The config file is still named **`cdktf.json`**, not `cdktn.json`. The fork kept the filename. Renaming it makes the CLI fail with "Could not find cdktf.json".
- Defaults are `output: "cdktf.out"` and `codeMakerOutput: ".gen"`. Both are overridable; set `output` to `cdktn.out` if you want the directory name to match the tool.
- `languageOptions.importExtension: ".js"` makes `cdktn get` emit ESM-ready relative imports (`export * as account from './account/index.js'`). This is a CDKTN addition with no CDKTF equivalent, and it is what lets the project be `"type": "module"` with `moduleResolution: "NodeNext"`. Set it before the first `cdktn get`.
- There are **no prebuilt provider packages** for CDKTN. Any `@cdktf/provider-<name>` dependency must be replaced by a `terraformProviders` entry in `cdktf.json` plus a `cdktn get`.
- `cdktn get` runs the project's package manager internally. Never wire it to `postinstall` or `prepare` — it recurses. Make it an explicit `pnpm get` step in the README instead.
- `cdktn get` output is large (tens of MB for a big provider). Gitignore `.gen/` and document `pnpm get` as an install step.

## Workflow

1. **Inspect before editing.**
   - `git status --short --branch`.
   - Read `.projenrc.ts`, `package.json`, `cdktf.json`, `tsconfig.json`, `biome.jsonc`, every stack file, `README.md`, `LICENSE`, and any workflow files.
   - Note the provider constraints, construct IDs, stack IDs, and stack names. Preserve them unless the user asks otherwise — construct ID changes force resource replacement.
   - Check whether the app actually synthesized and deployed before. A Projen CDKTF app that was never deployed often has real bugs (dangling asset paths, missing build steps) that the migration must fix, not carry over.

2. **Swap the library.**
   - `cdktf` → `cdktn`, `cdktf-cli` → `cdktn-cli` in `package.json`. Both go to the newest stable version.
   - Rewrite every `from "cdktf"` import to `from "cdktn"`.
   - Replace `@cdktf/provider-*` dependencies with `terraformProviders` entries in `cdktf.json`.
   - Update scripts from `cdktf <cmd>` to `cdktn <cmd>`, and `npx projen <task>` to real commands.

3. **Rewrite `cdktf.json`.** See `references/project-shape.md` for the target file.

4. **Move the app to ESM.**
   - `"type": "module"` in `package.json`; `module`/`moduleResolution: "NodeNext"` in `tsconfig.json`.
   - Add `.js` specifiers to every relative import in `src/` and `test/`.
   - Replace `__dirname` with `dirname(fileURLToPath(import.meta.url))`.
   - Set `app` to `node --import tsx src/main.ts`.

5. **Delete generated Projen state.** `.projen/`, `.projenrc.ts`, `tsconfig.dev.json`, `.npmignore`, `.npmrc`, `.mergify.yml`, Projen-generated GitHub Actions workflows, `.github/pull_request_template.md` when it is the stock Projen one, and lockfiles other than `pnpm-lock.yaml`.

6. **Replace the test setup.** Jest + ts-jest + `jest-junit` go away; Vitest replaces them. Do not port a `toMatchSnapshot` placeholder — a snapshot of a whole synthesized stack fails on every provider bump and asserts nothing. Write assertions on the properties that matter instead, using the built-in helpers, which take the JSON string returned by `Testing.synth`:

   ```ts
   Testing.toHaveProvider(synthesized, "cloudflare");
   Testing.toHaveResourceWithProperties(synthesized, "cloudflare_workers_script", { ... });
   Testing.toHaveDataSourceWithProperties(synthesized, "cloudflare_accounts", { ... });
   ```

   `Testing.toBeValidTerraform` takes a **path** from `Testing.fullSynth`, not the JSON string from `Testing.synth`. Passing the JSON string silently returns `false`. Prefer `Testing.synth(stack, true)` for construct-level validation and a real `terraform validate` outside the test run.

7. **Generate bindings and validate.**
   ```sh
   mise install
   pnpm install
   pnpm get
   pnpm lint && pnpm typecheck && pnpm test && pnpm synth
   ```
   Then prove the synthesized output is real Terraform, which unit tests do not cover:
   ```sh
   cd <output>/stacks/<stack-id> && terraform init && terraform validate
   ```
   Run `cdktn diff` too when credentials are available. Never `cdktn deploy` unless the user asks.

## Bundled application code

CDKTF apps that ship a Lambda, a Worker, or any other bundled artifact need a build step that Projen used to imply. Two rules:

- **Build with the platform's own bundler, not a hand-rolled esbuild config.** For Cloudflare Workers that means keeping a `wrangler.jsonc` purely for bundling and running `wrangler deploy --dry-run --outdir dist`; Wrangler owns the `nodejs_compat` polyfills and module aliases that a bare esbuild invocation silently gets wrong. Terraform still owns the deploy. Chain it: `"synth": "pnpm bundle && cdktn synth"`.
- **Hand the artifact to Terraform through `TerraformAsset`,** not an absolute path and not by inlining the file:

  ```ts
  const bundle = new TerraformAsset(this, "WorkerBundle", {
    path: join(projectRoot, "dist", "index.js"),
    type: AssetType.FILE,
  });
  // → content_file: "assets/WorkerBundle/<hash>/index.js"
  ```

  `TerraformAsset` copies the file into the stack's synth directory and yields a path relative to it, so the synthesized output stays portable. `Fn.file(absolutePath)` bakes a machine-specific path into the config, and reading the file in Node embeds megabytes into both the config and the state file.

  Prefer a provider's `*_file` + `*_sha256` argument pair over an inline content argument whenever it offers one.

## Decisions

- mise owns Node, pnpm, and the Terraform/OpenTofu binary. Add `terraform` to the repo's `mise.toml` — CDKTN needs it and it is not implied by Node.
- No `packageManager`, `engines`, or `devEngines` in `package.json`; `mise.toml` owns tool versions.
- Keep `pnpm-workspace.yaml` explicit with `minimumReleaseAgeStrict: true`. Deep dependency trees (Stagehand, Playwright, protobuf-based SDKs) will surface `ERR_PNPM_IGNORED_BUILDS`; resolve it by setting each package to `true` or `false` in `allowBuilds` after checking what its install script does, never with a blanket bypass.
- Do not regenerate the GitHub Actions workflows Projen created.
- License to MIT unless the repo has a reason to stay on Apache-2.0.
- "Latest stable" yields to a documented runtime constraint. Record the constraint and the reason in the README rather than pinning silently — a package whose current major cannot run in the target runtime is a compatibility constraint, not a version to upgrade to.

## Finish

Report which commands were run and which passed, whether `terraform validate` succeeded, and anything that could not be verified locally for lack of credentials.
