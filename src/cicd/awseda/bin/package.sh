#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../../helpers/loaders.sh"
source "${SCRIPT_DIR}/../../../helpers/domains/awseda.sh"

load_project_variables
awseda_load_manifest

packaged_count=0
staging_dir=

function clean_staging_dir() {
  if [ -n "${staging_dir}" ] && [ -d "${staging_dir}" ]; then
    rm -rf "${staging_dir}"
  fi
}

trap clean_staging_dir EXIT

while IFS= read -r function_id; do
  if ! awseda_function_changed "${function_id}"; then
    echo " - Skipping unchanged Lambda ${function_id}"
    continue
  fi

  function_source=$(awseda_query -r --arg function_id "${function_id}" '.lambda.functions[$function_id].source // empty')
  configured_build=$(awseda_query -r --arg function_id "${function_id}" '.lambda.functions[$function_id].build // "dist"')

  if [ -z "${function_source}" ]; then
    echo "Lambda ${function_id} requires a source path in ${AWS_EDA_CONFIG_FILE}" >&2
    exit 1
  fi

  function_dir="${PROJECT_DIR}/${function_source}"
  function_package="${function_dir}/package.json"
  function_build="${function_dir}/${configured_build}"
  artifact_path=$(awseda_function_artifact_path "${function_id}")
  staging_dir=$(mktemp -d)

  if [ ! -d "${function_dir}" ]; then
    echo "Missing source directory for Lambda ${function_id}: ${function_dir}" >&2
    exit 1
  fi
  if [ ! -f "${function_package}" ]; then
    echo "Missing package.json for Lambda ${function_id}" >&2
    exit 1
  fi

  echo " - Building Lambda ${function_id}"
  npm run build --prefix "${function_dir}"

  if [ ! -d "${function_build}" ]; then
    echo "Lambda ${function_id} build did not create ${function_build}" >&2
    exit 1
  fi

  cp -R "${function_build}/." "${staging_dir}/"
  cp "${function_package}" "${staging_dir}/package.json"

  while IFS=$'\t' read -r dependency_name dependency_reference; do
    dependency_source=$(cd "${function_dir}" && cd "${dependency_reference#file:}" && pwd)
    dependency_slug=$(echo "${dependency_name}" | tr '@/ ' '___')
    dependency_target=".workspace-dependencies/${dependency_slug}"
    mkdir -p "${staging_dir}/${dependency_target}"
    cp -R "${dependency_source}/." "${staging_dir}/${dependency_target}/"
    jq --arg name "${dependency_name}" --arg path "file:${dependency_target}" '.dependencies[$name] = $path' \
      "${staging_dir}/package.json" > "${staging_dir}/package.json.tmp"
    mv "${staging_dir}/package.json.tmp" "${staging_dir}/package.json"
  done < <(jq -r '(.dependencies // {}) | to_entries[] | select(.value | startswith("file:")) | [.key, .value] | @tsv' "${function_package}")

  echo " - Installing production dependencies for Lambda ${function_id}"
  npm install --prefix "${staging_dir}" --omit=dev --ignore-scripts --install-links --package-lock=false
  rm -rf "${staging_dir}/.workspace-dependencies"

  echo " - Packaging Lambda ${function_id} as ${artifact_path}"
  mkdir -p "$(dirname "${artifact_path}")"
  rm -f "${artifact_path}"
  if command -v zip >/dev/null 2>&1; then
    (
      cd "${staging_dir}"
      zip -q -r "${artifact_path}" .
    )
  elif [ -x "${PROJECT_DIR}/src/node_modules/.bin/bestzip" ]; then
    (
      cd "${staging_dir}"
      "${PROJECT_DIR}/src/node_modules/.bin/bestzip" "${artifact_path}" .
    )
  else
    echo "Packaging Lambda ${function_id} requires zip or the root bestzip development dependency" >&2
    exit 1
  fi
  rm -rf "${staging_dir}"
  staging_dir=
  packaged_count=$((packaged_count + 1))
done < <(awseda_query -r '.lambda.functions | keys[]')

if [ "${packaged_count}" -eq 0 ]; then
  echo " - No affected Lambda functions to package"
fi

if awseda_graphql_changed; then
  graphql_source=$(awseda_query -r '.appsync.graphql.api.source // empty')
  graphql_dir="${PROJECT_DIR}/${graphql_source}"
  graphql_schema=$(awseda_graphql_schema_path)

  if [ -z "${graphql_source}" ] || [ ! -d "${graphql_dir}" ]; then
    echo "GraphQL API requires a source directory in ${AWS_EDA_CONFIG_FILE}" >&2
    exit 1
  fi

  echo " - Packaging GraphQL schema as ${graphql_schema}"
  GRAPHQL_SCHEMA_ARTIFACT="${graphql_schema}" npm run build --prefix "${PROJECT_DIR}/src"

  if [ ! -f "${graphql_schema}" ]; then
    echo "GraphQL build did not create ${graphql_schema}" >&2
    exit 1
  fi
else
  echo " - Skipping unchanged GraphQL API"
fi
