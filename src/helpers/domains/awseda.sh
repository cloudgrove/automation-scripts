function awseda_load_manifest() {
  local configured_manifest=${DEPLOYMENT_MANIFEST:-.cloudgrove/deployment-manifest.yml}

  if [[ "${configured_manifest}" = /* ]]; then
    AWS_EDA_CONFIG_FILE=${AWS_EDA_CONFIG_FILE:-${configured_manifest}}
  else
    AWS_EDA_CONFIG_FILE=${AWS_EDA_CONFIG_FILE:-${PROJECT_DIR}/${configured_manifest}}
  fi

  if [ ! -f "${AWS_EDA_CONFIG_FILE}" ]; then
    echo "Missing AWS EDA configuration: ${AWS_EDA_CONFIG_FILE}" >&2
    return 1
  fi
  if ! command -v yq >/dev/null 2>&1; then
    echo "yq is required to read ${AWS_EDA_CONFIG_FILE}" >&2
    return 1
  fi

  if [ -n "${AWS_EDA_CHANGED_FILES:-}" ]; then
    return 0
  fi

  local base_sha=${AWS_EDA_BASE_SHA:-}
  if [ -z "${base_sha}" ] && git -C "${PROJECT_DIR}" rev-parse HEAD^ >/dev/null 2>&1; then
    base_sha=HEAD^
  fi

  AWS_EDA_CHANGED_FILES=$(
    {
      if [ -n "${base_sha}" ]; then
        git -C "${PROJECT_DIR}" diff --name-only "${base_sha}" HEAD
      fi
      git -C "${PROJECT_DIR}" diff --name-only HEAD
      git -C "${PROJECT_DIR}" ls-files --others --exclude-standard
    } | sort -u
  )
}

function awseda_load_config() {
  awseda_load_manifest

  ENV=${ENV:-$(awseda_query -r '.default.environment // empty')}
  if [ -z "${ENV}" ]; then
    echo "ENV or default.environment in the deployment manifest is required" >&2
    return 1
  fi

  AWS_EDA_REVISION=${AWS_EDA_REVISION:-$(git -C "${PROJECT_DIR}" rev-parse HEAD)}
  AWS_EDA_LAMBDA_ARTIFACT_BUCKET=${AWS_EDA_LAMBDA_ARTIFACT_BUCKET:-$(awseda_render \
    "$(awseda_query -r '.lambda.artifact.bucket // empty')")}
  AWS_EDA_LAMBDA_ARTIFACT_PATH=${AWS_EDA_LAMBDA_ARTIFACT_PATH:-$(awseda_render \
    "$(awseda_query -r '.lambda.artifact.path // empty')")}
  AWS_EDA_GRAPHQL_ARTIFACT_BUCKET=${AWS_EDA_GRAPHQL_ARTIFACT_BUCKET:-$(awseda_render \
    "$(awseda_query -r '.appsync.graphql.artifact.bucket // empty')")}
  AWS_EDA_GRAPHQL_ARTIFACT_PATH=${AWS_EDA_GRAPHQL_ARTIFACT_PATH:-$(awseda_render \
    "$(awseda_query -r '.appsync.graphql.artifact.path // empty')")}

  if [ -z "${AWS_EDA_LAMBDA_ARTIFACT_BUCKET}" ] || [ -z "${AWS_EDA_LAMBDA_ARTIFACT_PATH}" ]; then
    echo "lambda.artifact.bucket and lambda.artifact.path are required in the deployment manifest" >&2
    return 1
  fi
  if [ -z "${AWS_EDA_GRAPHQL_ARTIFACT_BUCKET}" ] || [ -z "${AWS_EDA_GRAPHQL_ARTIFACT_PATH}" ]; then
    echo "appsync.graphql.artifact.bucket and appsync.graphql.artifact.path are required in the deployment manifest" >&2
    return 1
  fi
}

function awseda_query() {
  yq -o=json '.' "${AWS_EDA_CONFIG_FILE}" | jq "$@"
}

function awseda_render() {
  local value=$1
  value=${value//\$\{env\}/${ENV}}
  echo "${value//\$\{version\}/${AWS_EDA_REVISION}}"
}

function awseda_function_artifact_key() {
  local function_id=$1
  local configured_name
  local function_name

  configured_name=$(awseda_query -r --arg function_id "${function_id}" '.lambda.functions[$function_id].name')
  function_name=$(awseda_render "${configured_name}")
  echo "${AWS_EDA_LAMBDA_ARTIFACT_PATH%/}/${function_name}.zip"
}

function awseda_function_artifact_path() {
  local function_id=$1
  local configured_artifact

  configured_artifact=$(awseda_query -r --arg function_id "${function_id}" \
    '.lambda.functions[$function_id].artifact // ("src/dist/" + $function_id + ".zip")')
  echo "${PROJECT_DIR}/${configured_artifact}"
}

function awseda_graphql_schema_path() {
  local configured_schema

  configured_schema=$(awseda_query -r '.appsync.graphql.api.schema // "src/dist/api/graphql/schema.graphql"')
  echo "${PROJECT_DIR}/${configured_schema}"
}

function awseda_graphql_schema_key() {
  echo "${AWS_EDA_GRAPHQL_ARTIFACT_PATH%/}/schema.graphql"
}

function awseda_graphql_resolver_key() {
  local resolver_file=$1
  echo "${AWS_EDA_GRAPHQL_ARTIFACT_PATH%/}/$(basename "${resolver_file}")"
}

function awseda_graphql_resolver_dir() {
  local configured_source

  configured_source=$(awseda_query -r '.appsync.graphql.api.source')
  echo "${PROJECT_DIR}/${configured_source}/resolvers"
}

function awseda_graphql_changed() {
  local configured_source
  local config_path
  local changed_path

  if ! awseda_query -e '.appsync.graphql' >/dev/null; then
    return 1
  fi

  if [ -n "${AWS_EDA_COMPONENTS:-}" ]; then
    case ",${AWS_EDA_COMPONENTS}," in
      *,all,*|*,appsync,*|*,graphql,*)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  fi

  configured_source=$(awseda_query -r '.appsync.graphql.api.source // empty')
  config_path="${AWS_EDA_CONFIG_FILE#${PROJECT_DIR}/}"
  while IFS= read -r changed_path; do
    case "${changed_path}" in
      "${configured_source}"|"${configured_source}"/*|src/package.json|src/package-lock.json|"${config_path}")
        return 0
        ;;
    esac
  done <<< "${AWS_EDA_CHANGED_FILES}"

  return 1
}

function awseda_load_affected_functions() {
  if [ "${AWS_EDA_AFFECTED_FUNCTIONS+x}" = x ]; then
    return 0
  fi

  local helper_dir
  helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  AWS_EDA_AFFECTED_FUNCTIONS=$(
    awseda_query -c '.lambda.functions // {}' |
      PROJECT_DIR="${PROJECT_DIR}" \
      AWS_EDA_CONFIG_FILE="${AWS_EDA_CONFIG_FILE}" \
      AWS_EDA_CHANGED_FILES="${AWS_EDA_CHANGED_FILES}" \
      node "${helper_dir}/select-affected-functions.js"
  )
}

function awseda_function_changed() {
  local function_id=$1
  local affected_function

  if [ -n "${AWS_EDA_COMPONENTS:-}" ]; then
    case ",${AWS_EDA_COMPONENTS}," in
      *,all,*|*,"${function_id}",*)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  fi

  awseda_load_affected_functions
  while IFS= read -r affected_function; do
    if [ "${affected_function}" = "${function_id}" ]; then
      return 0
    fi
  done <<< "${AWS_EDA_AFFECTED_FUNCTIONS}"

  return 1
}

function awseda_push_function_artifacts() {
  awseda_load_config

  while IFS= read -r function_id; do
    local artifact_key
    local artifact_path

    if ! awseda_function_changed "${function_id}"; then
      echo " - Skipping unchanged Lambda ${function_id}"
      continue
    fi

    artifact_path=$(awseda_function_artifact_path "${function_id}")
    artifact_key=$(awseda_function_artifact_key "${function_id}")

    if [ ! -f "${artifact_path}" ]; then
      echo "Missing artifact for ${function_id}: ${artifact_path}" >&2
      return 1
    fi

    echo " - Pushing ${function_id} artifact to s3://${AWS_EDA_LAMBDA_ARTIFACT_BUCKET}/${artifact_key}"
    aws s3 cp "${artifact_path}" "s3://${AWS_EDA_LAMBDA_ARTIFACT_BUCKET}/${artifact_key}" --only-show-errors
  done < <(awseda_query -r '.lambda.functions | keys[]')
}

function awseda_push_graphql_artifacts() {
  awseda_load_config

  if ! awseda_graphql_changed; then
    echo " - Skipping unchanged GraphQL API"
    return 0
  fi

  local resolver_dir
  local resolver_file
  local resolver_key
  local schema_key
  local schema_path

  schema_path=$(awseda_graphql_schema_path)
  schema_key=$(awseda_graphql_schema_key)
  resolver_dir=$(awseda_graphql_resolver_dir)

  if [ ! -f "${schema_path}" ]; then
    echo "Missing packaged GraphQL schema: ${schema_path}" >&2
    return 1
  fi

  echo " - Pushing GraphQL schema to s3://${AWS_EDA_GRAPHQL_ARTIFACT_BUCKET}/${schema_key}"
  aws s3 cp "${schema_path}" "s3://${AWS_EDA_GRAPHQL_ARTIFACT_BUCKET}/${schema_key}" --only-show-errors

  while IFS= read -r resolver_file; do
    resolver_key=$(awseda_graphql_resolver_key "${resolver_file}")
    echo " - Pushing resolver set to s3://${AWS_EDA_GRAPHQL_ARTIFACT_BUCKET}/${resolver_key}"
    aws s3 cp "${resolver_file}" "s3://${AWS_EDA_GRAPHQL_ARTIFACT_BUCKET}/${resolver_key}" --only-show-errors
  done < <(find "${resolver_dir}" -type f \( -name '*.yml' -o -name '*.yaml' -o -name '*.js' -o -name '*.mjs' \) | sort)
}

function awseda_deploy_functions() {
  awseda_load_config

  while IFS= read -r function_id; do
    local artifact_key
    local configured_name
    local function_name

    if ! awseda_function_changed "${function_id}"; then
      echo " - Skipping unchanged Lambda ${function_id}"
      continue
    fi

    configured_name=$(awseda_query -r --arg function_id "${function_id}" '.lambda.functions[$function_id].name')
    function_name=$(awseda_render "${configured_name}")
    artifact_key=$(awseda_function_artifact_key "${function_id}")

    echo " - Deploying ${function_id} code to ${function_name}"
    aws lambda update-function-code \
      --function-name "${function_name}" \
      --s3-bucket "${AWS_EDA_LAMBDA_ARTIFACT_BUCKET}" \
      --s3-key "${artifact_key}" \
      --output json >/dev/null
    aws lambda wait function-updated-v2 --function-name "${function_name}"
  done < <(awseda_query -r '.lambda.functions | keys[]')
}

function awseda_wait_for_schema() {
  local api_id=$1
  local attempts=0
  local status
  local details

  while [ "${attempts}" -lt 60 ]; do
    status=$(aws appsync get-schema-creation-status --api-id "${api_id}" --query status --output text)
    case "${status}" in
      SUCCESS)
        return 0
        ;;
      FAILED)
        details=$(aws appsync get-schema-creation-status --api-id "${api_id}" --query details --output text)
        echo "AppSync schema deployment failed: ${details}" >&2
        return 1
        ;;
    esac
    attempts=$((attempts + 1))
    sleep 2
  done

  echo "Timed out waiting for AppSync schema deployment" >&2
  return 1
}

function awseda_deploy_graphql() {
  awseda_load_config

  if ! awseda_graphql_changed; then
    echo " - Skipping unchanged GraphQL API"
    return 0
  fi

  local api_name
  local graphql_api_id
  local schema_path
  local configured_name
  local resolver_code
  local resolver_code_path
  local resolver_data_source
  local resolver_file
  local resolver_json
  local resolver_runtime_name
  local resolver_runtime_version
  local resolver_type
  local resolver_field
  local resolver_dir
  local -a resolver_args

  configured_name=$(awseda_query -r '.appsync.graphql.api.name')
  api_name=$(awseda_render "${configured_name}")
  graphql_api_id=$(aws appsync list-graphql-apis \
    --query "graphqlApis[?name=='${api_name}'].apiId | [0]" \
    --output text)
  schema_path=$(awseda_graphql_schema_path)
  resolver_dir=$(awseda_graphql_resolver_dir)

  if [ -z "${graphql_api_id}" ] || [ "${graphql_api_id}" = "None" ]; then
    echo "Unable to find AppSync GraphQL API ${api_name}" >&2
    return 1
  fi
  if [ ! -f "${schema_path}" ]; then
    echo "Missing packaged GraphQL schema: ${schema_path}" >&2
    return 1
  fi

  echo " - Deploying schema to ${api_name}"
  aws appsync start-schema-creation \
    --api-id "${graphql_api_id}" \
    --definition "fileb://${schema_path}" \
    --output json >/dev/null
  awseda_wait_for_schema "${graphql_api_id}"

  while IFS= read -r resolver_file; do
    while IFS= read -r resolver_json; do
      resolver_type=$(jq -r '.type' <<< "${resolver_json}")
      resolver_field=$(jq -r '.field' <<< "${resolver_json}")
      resolver_data_source=$(jq -r '.data_source' <<< "${resolver_json}")
      resolver_code=$(jq -r '.code // empty' <<< "${resolver_json}")
      resolver_runtime_name=$(jq -r '.runtime.name // empty' <<< "${resolver_json}")
      resolver_runtime_version=$(jq -r '.runtime.version // empty' <<< "${resolver_json}")
      resolver_args=(
        --api-id "${graphql_api_id}"
        --type-name "${resolver_type}"
        --field-name "${resolver_field}"
        --data-source-name "${resolver_data_source}"
        --kind UNIT
      )
      if [ -n "${resolver_code}" ]; then
        resolver_code_path="${resolver_dir}/${resolver_code}"
        if [ -z "${resolver_runtime_name}" ] || [ -z "${resolver_runtime_version}" ]; then
          echo "Resolver ${resolver_type}.${resolver_field} requires runtime.name and runtime.version when code is configured" >&2
          return 1
        fi
        if [ ! -f "${resolver_code_path}" ]; then
          echo "Missing resolver code for ${resolver_type}.${resolver_field}: ${resolver_code_path}" >&2
          return 1
        fi
        resolver_args+=(
          --runtime "name=${resolver_runtime_name},runtimeVersion=${resolver_runtime_version}"
          --code "file://${resolver_code_path}"
        )
      fi
      if aws appsync get-resolver \
        --api-id "${graphql_api_id}" \
        --type-name "${resolver_type}" \
        --field-name "${resolver_field}" \
        --output json >/dev/null 2>&1; then
        echo " - Updating ${resolver_type}.${resolver_field}"
        aws appsync update-resolver "${resolver_args[@]}" --output json >/dev/null
      else
        echo " - Creating ${resolver_type}.${resolver_field}"
        aws appsync create-resolver "${resolver_args[@]}" --output json >/dev/null
      fi
    done < <(yq -o=json '.' "${resolver_file}" | jq -c '.[]')
  done < <(find "$(awseda_graphql_resolver_dir)" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
}
