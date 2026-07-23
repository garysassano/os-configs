---
name: projen-cdk-ts-refactor
description: Convert existing Projen-managed AWS CDK TypeScript apps to the local pnpm 11 CDK scaffold. Use when a repo has `.projenrc.ts`, `.projen/`, Projen-generated package scripts, Jest/ts-jest placeholder tests, Projen-generated GitHub Actions workflows, npm/yarn/bun leftovers, or the user asks to remove Projen from a CDK TypeScript app.
---

# Projen CDK TypeScript Refactor

## Overview

Use this skill for migrations, not new scaffolds. The goal is to preserve the existing CDK infrastructure code while replacing Projen-managed project shell files with the local pnpm-based CDK scaffold.

The clean scaffold is owned by the `cdk-scaffolding` skill and its script. This skill owns the refactor decisions around what generated Projen state to delete, what repo-specific behavior to preserve, and how to validate the converted app.

## Workflow

1. Inspect before editing.
   - Run `git status --short --branch`.
   - Read `.projenrc.ts`, `package.json`, `cdk.json`, `tsconfig.json`, `biome.jsonc`, existing stack files, README, LICENSE, and workflow files when present.
   - Identify meaningful user-authored files versus generated Projen/project-shell files.
   - Preserve infrastructure code, construct IDs, stack names, environment defaults, and README details unless the user asks to change them.

2. Apply the clean scaffold shell.
   - Run `/home/user/.codex/skills/cdk-scaffolding/scripts/scaffold-cdk-project.mjs --target <repo> --resolve-latest`.
   - Pass `--name`, `--stack-class`, `--stack-file`, `--stack-id`, or `--node-min` when needed to preserve the existing repo shape.
   - Expect the scaffold to write pnpm 11, TypeScript, Biome, `node --import tsx src/main.ts`, MIT license, README skeleton, `pnpm-workspace.yaml`, and no GitHub Actions workflows.

3. Delete obsolete generated files.
   - Remove `.projen/`, `.projenrc.ts`, `tsconfig.dev.json`, `.npmignore`, `.mergify.yml`, `.npmrc`, Projen-generated GitHub Actions workflows, and generic Projen PR lint/build workflow files when the repo does not need them.
   - Remove obsolete package-manager files such as `package-lock.json`, `yarn.lock`, `bun.lock`, and `bunfig.toml`.
   - Remove placeholder tests that only snapshot a stack or import the app entrypoint and no longer have a test runner. Preserve real tests that protect resource properties, IAM, runtime settings, logical IDs, or other project invariants.
   - Remove stray one-off artifacts only after confirming they are not referenced, such as local trace payloads or manual test output.

4. Repair repo-specific code after the scaffold.
   - Convert CDK app runtime assumptions from CommonJS/ts-node to ESM/tsx where needed.
   - Replace `__dirname` with `fileURLToPath(import.meta.url)` or another ESM-safe path.
   - Convert Lambda handler samples to ESM exports when TypeScript/module settings require it.
   - Keep dependencies that the infrastructure actually needs. For example, `NodejsFunction` requires `esbuild`, even when the repo has no Vitest/Jest.

5. Validate.
   - Run `pnpm install` or `pnpm install --lockfile-only` as appropriate.
   - Run `pnpm lint`, `pnpm typecheck`, and `pnpm synth`; `pnpm check` is preferred when the scaffold defines it.
   - If `Vpc.fromLookup` or other context providers need account/region, first try the repo’s existing `cdk.context.json` and environment defaults. Use an AWS profile only when local validation genuinely needs live lookups.
   - Run `git diff --check` before committing.

## Decisions

- `packageManager` should not pin a pnpm patch release. Let `engines.pnpm: ">=11 <12"` express the pnpm 11 constraint.
- Do not keep generic GitHub Actions workflows just because Projen generated them.
- Do not add a test framework unless the repo has meaningful assertions to run.
- Keep `allowBuilds` explicit in `pnpm-workspace.yaml`; add packages only after confirming their lifecycle scripts are expected.
- Keep the README concise and repo-specific, matching the local `cdk-aws-*` pattern.

## Finish

If the user asked to update the repo, carry through to a clean worktree or a pushed commit when that matches the surrounding workflow. Report validation commands and any CDK annotations or warnings that remain.
