---
name: aws-cdk-defaults
description: Personal property defaults for AWS CDK constructs, overriding what the vendored aws-cdk skill or general AWS knowledge would otherwise suggest. Use when authoring or reviewing a CDK construct and a property value has to be chosen.
---

# AWS CDK Defaults

Personal preferences that take precedence over defaults suggested by the vendored `aws-cdk` skill or by general AWS knowledge. For CDK authoring, deployment, drift, refactoring, and troubleshooting beyond these property choices, use the aws-cdk skill.

Scope: one section per AWS service, covering only the properties where a specific value is wanted. Anything not listed here follows the aws-cdk skill.

Examples are TypeScript `aws-cdk-lib`, which is the default. Translate to the equivalent construct property when the project is in another language.

## Lambda

### Runtime

- Before choosing a Lambda runtime, check the official AWS Lambda supported runtimes table: https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html
- Prefer the latest supported managed runtime for new functions unless the project has a compatibility constraint.
- Set `runtime` to the matching `lambda.Runtime` constant when the installed `aws-cdk-lib` supports it, such as `lambda.Runtime.NODEJS_24_X` for Node.js 24. If the constant is missing, update `aws-cdk-lib` rather than silently falling back to an older runtime.

### Logging

- Set `loggingFormat: lambda.LoggingFormat.JSON` for new functions, unless the workflow depends on plain-text logs or embedded metric format compatibility has to be tested first.
- Set application and system log levels through the V2 properties `applicationLogLevelV2` and `systemLogLevelV2`, which require JSON logging.
- In handler code, use the runtime's own logging methods (`console.*` for Node.js, standard `logging` for Python), or Powertools when richer structured logs are needed.
