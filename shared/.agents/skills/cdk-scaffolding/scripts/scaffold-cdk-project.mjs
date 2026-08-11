#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, relative, resolve, sep } from "node:path";

const DEFAULT_NODE_VERSION = "24";
const DEFAULT_MINIMUM_RELEASE_AGE_MINUTES = 1440;
const DEFAULT_STACK_CLASS = "MyStack";
const DEFAULT_STACK_FILE = "src/stacks/my-stack.ts";
const DEFAULT_LICENSE_OWNER = "Gary Sassano";

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--help" || token === "-h") {
      args.help = true;
      continue;
    }
    if (!token.startsWith("--")) {
      throw new Error(`Unexpected argument: ${token}`);
    }
    const key = token.slice(2);
    if (key === "resolve-latest") {
      args.resolveLatest = true;
      continue;
    }
    const value = argv[i + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for --${key}`);
    }
    args[toCamelCase(key)] = value;
    i += 1;
  }
  return args;
}

function toCamelCase(value) {
  return value.replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase());
}

function usage() {
  return `Usage: scaffold-cdk-project.mjs [options]

Options:
  --target <path>        Project directory. Defaults to the current directory.
  --name <name>          package.json name. Defaults to existing package name or directory name.
  --stack-class <name>   Stack class name. Defaults to MyStack.
  --stack-file <path>    Stack file path. Defaults to src/stacks/my-stack.ts.
  --stack-id <id>        CDK stack id. Defaults to <package-name>-dev.
  --node-version <ver>   Node version for mise.toml and @types/node. Defaults to ${DEFAULT_NODE_VERSION}.
  --node-min <version>   Deprecated alias for --node-version.
  --license-owner <name> Copyright owner for LICENSE. Defaults to ${DEFAULT_LICENSE_OWNER}.
  --license-year <year>  Copyright year for LICENSE. Defaults to the current year.
  --resolve-latest       Resolve newest stable npm versions outside pnpm's 24-hour quarantine.
  --help                 Show this help text.
`;
}

function readJsonIfExists(filePath) {
  if (!existsSync(filePath)) {
    return undefined;
  }
  return JSON.parse(readFileSync(filePath, "utf8"));
}

function writeText(filePath, contents) {
  mkdirSync(dirname(filePath), { recursive: true });
  writeFileSync(filePath, contents);
}

function writeJson(filePath, value) {
  writeText(filePath, `${JSON.stringify(value, undefined, 2)}\n`);
}

function removeIfExists(target, relativePath) {
  const path = join(target, relativePath);
  if (existsSync(path)) {
    rmSync(path, { recursive: true, force: true });
  }
}

function npmViewVersion(spec) {
  const stdout = execFileSync("npm", ["view", spec, "version", "--json"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
  const parsed = JSON.parse(stdout);
  return Array.isArray(parsed) ? parsed.at(-1) : parsed;
}

function packageNameFromSpec(spec) {
  if (spec.startsWith("@")) {
    const versionSeparator = spec.indexOf("@", 1);
    return versionSeparator === -1 ? spec : spec.slice(0, versionSeparator);
  }
  return spec.split("@", 1)[0];
}

function npmViewMatureVersion(spec) {
  const latestVersion = npmViewVersion(spec);
  const latestMajor = majorOf(latestVersion);
  const packageName = packageNameFromSpec(spec);
  const stdout = execFileSync("npm", ["view", packageName, "time", "--json"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
  const publishedTimes = JSON.parse(stdout);
  const cutoff = Date.now() - DEFAULT_MINIMUM_RELEASE_AGE_MINUTES * 60 * 1000;
  const eligibleVersions = Object.entries(publishedTimes)
    .filter(([version, publishedAt]) => {
      return (
        majorOf(version) === latestMajor &&
        !version.includes("-") &&
        Date.parse(publishedAt) <= cutoff
      );
    })
    .map(([version]) => version);
  const version = eligibleVersions.at(-1);
  if (!version) {
    throw new Error(`No stable ${spec} release is at least 24 hours old`);
  }
  return version;
}

function majorOf(version) {
  const match = version.match(/^(\d+)(?:\.|$)/);
  return match ? Number(match[1]) : undefined;
}

function caret(version) {
  return `^${version}`;
}

function posixPath(path) {
  return path.split(sep).join("/");
}

function importPath(fromFile, toFile) {
  const rel = posixPath(relative(dirname(fromFile), toFile)).replace(/\.ts$/, ".js");
  return rel.startsWith(".") ? rel : `./${rel}`;
}

function defaultStackFileContents(stackClass) {
  return `import type { StackProps } from "aws-cdk-lib";
import { Stack } from "aws-cdk-lib";
import type { Construct } from "constructs";

export class ${stackClass} extends Stack {
  constructor(scope: Construct, id: string, props: StackProps = {}) {
    super(scope, id, props);
  }
}
`;
}

function mainFileContents(stackClass, stackFile, stackId) {
  const mainFile = "src/main.ts";
  const stackImport = importPath(mainFile, stackFile);
  return `import { App } from "aws-cdk-lib";
import { ${stackClass} } from "${stackImport}";

const app = new App();

new ${stackClass}(app, "${stackId}", {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

app.synth();
`;
}

function tsconfigContents() {
  return {
    compilerOptions: {
      declaration: false,
      experimentalDecorators: true,
      forceConsistentCasingInFileNames: true,
      lib: ["ES2025"],
      module: "NodeNext",
      moduleResolution: "NodeNext",
      noEmit: true,
      noImplicitReturns: true,
      noUncheckedIndexedAccess: true,
      resolveJsonModule: true,
      rootDir: "./src",
      skipLibCheck: true,
      strict: true,
      strictPropertyInitialization: false,
      target: "ES2025",
      types: ["node"],
    },
    include: ["src/**/*.ts"],
    exclude: ["cdk.out", "coverage", "dist", "node_modules"],
  };
}

function biomeConfigContents(biomeVersion) {
  return `{
  "$schema": "https://biomejs.dev/schemas/${biomeVersion}/schema.json",
  "assist": {
    "actions": {
      "preset": "recommended",
      "source": {
        "organizeImports": {
          "level": "on",
          "options": {
            "identifierOrder": "lexicographic"
          }
        }
      }
    },
    "enabled": true
  },
  "files": {
    "ignoreUnknown": false,
    "includes": ["src/**", "package.json", "cdk.json"]
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100
  },
  "javascript": {
    "formatter": {
      "quoteStyle": "double"
    }
  },
  "linter": {
    "enabled": true,
    "rules": {
      "preset": "recommended",
      "suspicious": {
        "noShadowRestrictedNames": "off"
      }
    }
  },
  "vcs": {
    "clientKind": "git",
    "enabled": true,
    "useIgnoreFile": true
  }
}
`;
}

function cdkJsonContents() {
  return `{
  "app": "node --import tsx src/main.ts",
  "output": "cdk.out",
  "context": {
    "cli-telemetry": false
  },
  "watch": {
    "include": ["src/**/*.ts"],
    "exclude": ["README.md", "cdk*.json", "node_modules", "coverage", "dist"]
  }
}
`;
}

function pnpmWorkspaceContents() {
  return `packages:
  - "."

allowBuilds:
  esbuild: true

minimumReleaseAgeStrict: true
`;
}

function miseTomlContents(nodeVersion) {
  return `[tools]
node = "${nodeVersion}"
pnpm = "11"
`;
}

function gitignoreContents() {
  return `node_modules/
coverage/
dist/
lib/
logs/
*.log
*.tsbuildinfo
cdk.context.json
cdk.out/
.cdk.staging/
`;
}

function gitattributesContents() {
  return `* text=auto eol=lf
pnpm-lock.yaml text eol=lf
`;
}

function licenseContents(licenseOwner, licenseYear) {
  return `MIT License

Copyright (c) ${licenseYear} ${licenseOwner}

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
`;
}

function readmeContents(packageName) {
  return `# ${packageName}

CDK app that deploys AWS infrastructure using AWS CDK v2.

## Prerequisites

- **_AWS:_**
  - Must have authenticated with [Default Credentials](https://docs.aws.amazon.com/cdk/v2/guide/cli.html#cli-auth) in your local environment.
  - Must have completed the [CDK bootstrapping](https://docs.aws.amazon.com/cdk/v2/guide/bootstrapping.html) for the target AWS environment.
- **_mise:_**
  - [Install mise](https://mise.jdx.dev/installing-mise.html), which manages the required toolchain.

## Installation

\`\`\`sh
mise install
pnpm install
\`\`\`

## Deployment

\`\`\`sh
pnpm deploy
\`\`\`

## Cleanup

\`\`\`sh
pnpm destroy
\`\`\`
`;
}

function packageJson(existingPackage, values) {
  const packageName = values.packageName;
  return {
    name: packageName,
    version: existingPackage.version ?? "0.0.0",
    license: "MIT",
    type: "module",
    scripts: {
      cdk: "cdk",
      check: "pnpm lint && pnpm typecheck && pnpm synth",
      deploy: "cdk deploy",
      destroy: "cdk destroy",
      diff: "cdk diff",
      format: "biome format --write .",
      lint: "biome check .",
      "lint:fix": "biome check --write .",
      synth: "cdk synth --strict",
      typecheck: "tsc --noEmit",
    },
    dependencies: {
      "aws-cdk-lib": caret(values.versions.awsCdkLib),
      constructs: caret(values.versions.constructs),
    },
    devDependencies: {
      "@biomejs/biome": caret(values.versions.biome),
      "@types/node": caret(values.versions.typesNode),
      "aws-cdk": caret(values.versions.awsCdk),
      tsx: caret(values.versions.tsx),
      typescript: caret(values.versions.typescript),
      zod: caret(values.versions.zod),
    },
    ...(existingPackage.publishConfig ? { publishConfig: existingPackage.publishConfig } : {}),
    ...(existingPackage.private === true ? { private: true } : {}),
  };
}

function resolveVersions(resolveLatest, nodeMajor) {
  if (!resolveLatest) {
    return {
      awsCdkLib: "2.261.0",
      awsCdk: "2.1132.0",
      constructs: "10.7.1",
      typescript: "7.0.2",
      biome: "2.5.5",
      tsx: "4.23.1",
      typesNode: "24.13.3",
      zod: "4.4.3",
    };
  }

  const typescript = npmViewMatureVersion("typescript@7");
  if (majorOf(typescript) !== 7) {
    throw new Error(`Expected latest stable TypeScript major 7, got ${typescript}`);
  }

  return {
    awsCdkLib: npmViewMatureVersion("aws-cdk-lib"),
    awsCdk: npmViewMatureVersion("aws-cdk"),
    constructs: npmViewMatureVersion("constructs"),
    typescript,
    biome: npmViewMatureVersion("@biomejs/biome"),
    tsx: npmViewMatureVersion("tsx"),
    typesNode: npmViewMatureVersion(`@types/node@${nodeMajor}`),
    zod: npmViewMatureVersion("zod"),
  };
}

function run() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    process.stdout.write(usage());
    return;
  }

  const target = resolve(args.target ?? process.cwd());
  const existingPackage = readJsonIfExists(join(target, "package.json")) ?? {};
  const packageName = args.name ?? existingPackage.name ?? basename(target);
  const stackClass = args.stackClass ?? DEFAULT_STACK_CLASS;
  const stackFile = posixPath(args.stackFile ?? DEFAULT_STACK_FILE);
  const stackId = args.stackId ?? `${packageName}-dev`;
  const nodeVersion = args.nodeVersion ?? args.nodeMin ?? DEFAULT_NODE_VERSION;
  const licenseOwner = args.licenseOwner ?? DEFAULT_LICENSE_OWNER;
  const licenseYear = args.licenseYear ?? String(new Date().getFullYear());
  const nodeMajor = majorOf(nodeVersion);
  if (!nodeMajor) {
    throw new Error(`Could not determine Node major version from ${nodeVersion}`);
  }

  const versions = resolveVersions(Boolean(args.resolveLatest), nodeMajor);

  removeIfExists(target, ".projen");
  removeIfExists(target, ".projenrc.ts");
  removeIfExists(target, "tsconfig.dev.json");
  removeIfExists(target, ".npmrc");
  removeIfExists(target, ".npmignore");
  removeIfExists(target, ".mergify.yml");
  removeIfExists(target, "bun.lock");
  removeIfExists(target, "bunfig.toml");
  removeIfExists(target, "package-lock.json");
  removeIfExists(target, "yarn.lock");

  const absoluteStackFile = join(target, stackFile);
  if (!existsSync(absoluteStackFile)) {
    writeText(absoluteStackFile, defaultStackFileContents(stackClass));
  }

  writeJson(join(target, "package.json"), packageJson(existingPackage, {
    packageName,
    versions,
  }));
  writeText(join(target, "mise.toml"), miseTomlContents(nodeVersion));
  writeText(join(target, "cdk.json"), cdkJsonContents());
  writeJson(join(target, "tsconfig.json"), tsconfigContents());
  writeText(join(target, "src/main.ts"), mainFileContents(stackClass, stackFile, stackId));
  writeText(join(target, "biome.jsonc"), biomeConfigContents(versions.biome));
  writeText(join(target, "pnpm-workspace.yaml"), pnpmWorkspaceContents());
  writeText(join(target, ".gitignore"), gitignoreContents());
  writeText(join(target, ".gitattributes"), gitattributesContents());
  writeText(join(target, "LICENSE"), licenseContents(licenseOwner, licenseYear));
  writeText(join(target, "README.md"), readmeContents(packageName));

  process.stdout.write(`Scaffolded ${packageName} in ${target}\n`);
}

run();
