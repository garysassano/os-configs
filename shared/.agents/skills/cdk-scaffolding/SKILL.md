---
name: cdk-scaffolding
description: Scaffold clean AWS CDK TypeScript projects that should use mise-managed Node 24 and pnpm 11, Node runtime execution through tsx, Biome, TypeScript, cdk synth validation, MIT license, no generated tests, and no GitHub Actions workflows. Use for new CDK app scaffolds or intentional refreshes of a project shell. For converting existing Projen-managed CDK TypeScript apps, use the separate projen-cdk-ts-refactor skill.
---

# CDK Scaffolding

## Overview

Use this skill when creating a new AWS CDK TypeScript project or refreshing a clean project shell to the local mise-managed pnpm defaults.

The scaffold is intentionally small: CDK app code lives in `src/main.ts`, stacks live under `src/stacks/<stack-name>.ts`, project tooling is explicit in normal config files, and generated CI/test scaffolding is not created.

## Workflow

1. Inspect the repository before editing.
   - Check `git status --short --branch`.
   - Read existing `package.json`, `cdk.json`, `tsconfig.json`, `biome.jsonc`, and stack files when they exist.
   - If the repo is Projen-managed, switch to the `projen-cdk-ts-refactor` skill before editing.
   - Preserve existing infrastructure code and construct IDs unless the user explicitly asks to rewrite them.

2. Resolve current package versions.
   - Prefer the newest stable package versions that satisfy pnpm 11's default 24-hour release-age policy unless the user gives a constraint.
   - For Node types, match the declared Node runtime major. Example: Node `>=24.16.0` should use latest `@types/node@24`, not latest `@types/node` if latest is for a newer runtime.
   - For CDK v2, expect `aws-cdk-lib` and `aws-cdk` CLI versions to differ; use the latest stable version for each package.
   - For TypeScript, check the current stable release before creating a new project. TypeScript 7 is what upstream `cdk init` now generates, so it is the default here too. If the project needs the TypeScript compiler API or tooling that imports `typescript`, first check whether a stable TypeScript 7.1 or newer release has restored the needed API compatibility; otherwise stay on TypeScript 6 for that project.
   - Do not add `minimumReleaseAgeExclude` entries to use packages that are still inside pnpm's quarantine window. Select the newest eligible release instead unless the user explicitly requests a temporary exception.

3. Run the scaffold script.
   - Use `node "$HOME"/.agents/skills/cdk-scaffolding/scripts/scaffold-cdk-project.mjs --target <repo> --resolve-latest`.
   - Pass `--name`, `--stack-class`, `--stack-file`, `--stack-id`, or `--node-version` when the repo needs non-default values.
   - The script preserves an existing stack file and writes only the project shell around it.
   - Do not create `.github/`, GitHub Actions workflows, or other CI files.

4. Review generated project shell.
   - Treat `mise.toml` and `pnpm-workspace.yaml` as source-owned project config. Preserve intentional workspace package globs in monorepos; for single-package scaffolds, keep `packages: ["."]`, the pnpm 11 `allowBuilds` map, and `minimumReleaseAgeStrict: true` explicit.
   - Update scaffold-owned `LICENSE` and README files to the standard MIT license and concise AWS CDK app README pattern. Preserve README content worth keeping when it documents project-specific behavior.

5. Install and verify.
   - Run `mise install`.
   - Run `pnpm install`.
   - Confirm `pnpm install` did not add `minimumReleaseAgeExclude`. If it did, remove the exception, select the newest package version outside the 24-hour quarantine, and regenerate the lockfile.
   - Run `pnpm typecheck` and `pnpm synth`.
   - Use `cdk synth --strict` for CDK validation. Do not deploy unless the user asks for deployment or the task explicitly requires AWS-side verification.

## Upstream `cdk init` defaults

`cdk init app --language typescript` was reworked and now generates much of what this scaffold already did. Re-read `packages/aws-cdk/lib/init-templates/app/typescript/` in `aws-cdk-cli` before assuming any of this is still current; it was confirmed against `origin/main` at 2026-08-21.

What upstream now generates:

- `typescript: ~7.0.2`, `tsx: ^4.23.0`, `@types/node: ^24.10.1`.
- `module` and `moduleResolution` set to `NodeNext`, with `noEmit: true` and `isolatedModules: true`.
- `@swc/jest` as the Jest transform, replacing `ts-jest`.
- The app entrypoint imports from `aws-cdk-lib/core` rather than the `aws-cdk-lib` root. This scaffold now does the same, and so should hand-written code, including the specific `aws-cdk-lib/aws-<service>` subpaths for services.
- `cdk.json` runs `"npx tsc && npx tsx bin/<name>.ts"` — a typecheck on every CDK invocation, then execution through tsx.

Where this scaffold deliberately differs, and why:

- The CDK app command stays `node --import tsx src/main.ts`, without the `tsc` prefix. Typechecking belongs in `pnpm typecheck` and `pnpm check`, not on the hot path of every `cdk deploy`. Adopt the upstream form only if a project wants the typecheck enforced at synth time.
- Layout stays `src/main.ts` and `src/stacks/<stack-name>.ts` rather than `bin/` and `lib/`, matching the neighboring local `cdk-aws-*` repos.
- Biome replaces the upstream lint/format story, `ES2025` replaces `ES2022`, and no tests or `jest.config.js` are generated.

## Project Defaults

- Tool manager: mise, with generated `mise.toml`.
- Package manager: pnpm 11 from `mise.toml`.
- Runtime: Node 24 from `mise.toml`.
- Do not set `packageManager`, `engines`, or `devEngines` in generated `package.json`; `mise.toml` owns repo tool versions.
- CDK app command: `node --import tsx src/main.ts`.
- TypeScript module mode: use `module: "NodeNext"` and `moduleResolution: "NodeNext"`. Relative imports between TypeScript source files must use `.js` specifiers so TypeScript models Node ESM semantics while `tsx` resolves them to `.ts` at runtime.
- TypeScript: latest stable major for CLI-only CDK scaffolds. Use TypeScript 6 instead when compiler-API compatibility is required and the stable TypeScript 7 line has not restored it yet.
- Import from `aws-cdk-lib/core` and `aws-cdk-lib/aws-<service>`, never the `aws-cdk-lib` root. The root's `index.d.ts` re-exports ~400 service namespaces with `export *`, which is eager for the type checker: a three-line file that imports `App` from the root loads 2,636 declaration files instead of 645, and costs roughly 3x the `tsc` time and 4.5x the peak memory. Runtime cost is smaller (the compiled namespaces are lazy getters) but not zero.
- TypeScript config: keep the CLI-only config compact, use `ES2025`, set `isolatedModules: true` to match upstream `cdk init`, and retain `strict: true` without restating strict-mode sub-options that it already enables.
- Do not restate compiler defaults. `forceConsistentCasingInFileNames` has been on by default since TypeScript 5.0, `resolveJsonModule` is implied by `moduleResolution: NodeNext`, `declaration` is both default-false and moot under `noEmit`, and `experimentalDecorators` is legacy TypeScript that CDK does not use. TypeScript 7's own `tsc --init` emits none of them. Verify a default before adding an option back.
- `strictPropertyInitialization: false` is the one deliberate loosening. It stays because tightening it changes the rules for user-authored construct code, which is not a scaffold's call to make.
- Typecheck `test/` as well as `src/`, and do not set `rootDir` — it would reject a `test/` tree outside `src/`.
- Build: no bundler by default. CDK executes `src/main.ts` directly through `tsx`.
- Generated tests: none. Add a test framework only when the project has meaningful CDK assertions to protect.
- Lint and format: Biome using the project config generated by this skill.
- Biome schema: use the versioned HTTPS schema matching the installed Biome version. Do not couple editor schema resolution to a pnpm `node_modules` path.
- pnpm 11 workspace config: keep `pnpm-workspace.yaml` explicit because pnpm no longer reads settings from `package.json`; use `allowBuilds` for reviewed dependency lifecycle scripts and `minimumReleaseAgeStrict: true` to prevent automatic quarantine exceptions.
- Release-age exceptions: do not commit `minimumReleaseAgeExclude` entries unless the user explicitly requests a temporary exception.
- Dependency lifecycle scripts: only add packages to `allowBuilds` after reviewing that their install scripts are expected. Do not use broad build-script bypasses.
- License: MIT, with a generated `LICENSE` file using `Gary Sassano` as the default copyright owner.
- README: match the neighboring local `cdk-aws-*` app pattern: title, one-sentence purpose, a lowercase `mise` prerequisite linking the words `Install mise` directly to its installation guide and stating that it manages the required toolchain, installation with `mise install` before `pnpm install`, deployment, and cleanup.
- GitHub Actions: never generate workflow files.

## Script

The scaffold script is in `scripts/scaffold-cdk-project.mjs`. It creates missing `src/stacks/<stack-name>.ts` only when the chosen stack file does not already exist. For Projen migrations, use the separate refactor skill to decide which generated files should be deleted before or after running the script.
