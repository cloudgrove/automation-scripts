# About this repo
This repo hosts automation scripts.

# CI/CD Environment Variables

## NPM
- `NPM_VERSION_PREID` is optional, and can hold the suffix added to the version of the built NPM packages.

# AWS event-driven application scripts

Projects that package independently deployable AWS Lambda functions together with application-owned GraphQL schemas and
resolvers can set:

```text
PROJECT_TYPE=awseda/bin
```

The project must provide a workspace-root `package.json` with repository-wide `build`, `test`, and lint scripts. Each Lambda
declared in the deployment manifest must be an npm workspace with a `build` script. The root build script merges domain SDL
files for the configured GraphQL source. The shared `make package` lifecycle maps the Git diff to changed workspaces,
follows local workspace dependencies to select affected Lambdas, writes the selected ZIP artifacts, and writes an affected
GraphQL schema to
`src/dist/api/graphql/schema.graphql`. When Docker is unavailable, the build lifecycle runs the same test, lint, and packaging
flow directly.

Deployment is described by the YAML file referenced by `DEPLOYMENT_MANIFEST` in `project.env`, defaulting to
`.cloudgrove/deployment-manifest.yml`. Function entries map a source directory to an existing Lambda name. Their build
scripts write to a function-local `dist/` directory by default, with an optional `build` override, and their ZIP artifacts
default to
`src/dist/<function-id>.zip`, with an optional `artifact` override. The AppSync entry maps its colocated domain schemas and
resolver bindings to an existing GraphQL API. Paths are relative to the project root. Names can contain `${env}`, expanded from
`ENV` or the configuration's `default.environment`:

```yaml
default:
  environment: gamma
appsync:
  graphql:
    artifact:
      bucket: example-${env}-artifacts
      path: example-backend/${version}/appsync/graphql
    api:
      name: example-${env}-graphql
      source: src/main/api/graphql
lambda:
  artifact:
    bucket: example-${env}-artifacts
    path: example-backend/${version}/lambda
  functions:
    google-integration:
      name: example-${env}-google-integration
      source: src/main/functions/google-integration
```

Resolver-set YAML files live under `.cloudgrove/appsync/resolvers/` and require `type`, `field`, and `data_source` for each entry. A bare entry creates a standard unit resolver. An entry can deploy AppSync JavaScript from a path relative to the project root by adding `code`. The optional `runtime` stanza defaults to `APPSYNC_JS` version `1.0.0`:

```yaml
- type: Query
  field: getExample
  data_source: example_table
  runtime:
    name: APPSYNC_JS
    version: 1.0.0
  code: src/main/api/graphql/resolvers/example.mjs
```

`push` copies selected Lambda ZIPs, the compiled GraphQL schema, resolver sets, and JavaScript resolver sources to the configured artifact buckets and
paths without changing AWS compute resources. It appends the rendered Lambda filename, `schema.graphql`, or the resolver-set
filename to the applicable manifest path. `${version}` expands to the Git revision and `${env}` expands to the AWS
environment.
`deploy` updates selected Lambda functions from their S3 objects, then publishes the schema and resolvers directly from the
local build. Terraform or an equivalent infrastructure system must create the artifact bucket, Lambda functions, AppSync
APIs, data sources, and IAM roles before these scripts run.

Lambda selection uses the Git diff and npm workspace dependency graph; changing a shared workspace rebuilds every Lambda that
depends on it. Changes to the workspace-root package or lock file, or to the deployment manifest, rebuild every Lambda.
Local production dependencies declared with `file:` are copied into the isolated staging directory and installed as regular package contents, so shared workspaces are included in the resulting Lambda ZIP without repository-relative symlinks.
GraphQL selection is derived from its configured source directory. By default the comparison uses `HEAD^`; set
`AWS_EDA_BASE_SHA` for another comparison base, or set `AWS_EDA_COMPONENTS=google-integration` (comma-separated, or `all`) for
an explicit manual deployment.
