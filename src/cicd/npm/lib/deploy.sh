#!/bin/bash

set -e

SCRIPT_DIR="$(cd $(dirname $0) && pwd)"
. ${SCRIPT_DIR}/../../../helpers/loaders.sh

load_project_variables
if [ -n "${AWS_S3_BUCKET}" ]; then
  cd ${PROJECT_DIR}/src
  VERSION=$(npm version | sed -n "2s/'//g; 2s/,//; 2p" | awk '{print $NF}')
  VERSION_DIR="s3://${AWS_S3_BUCKET}/${AWS_S3_PROJECT_DIR}/${VERSION}"
  CURRENT_DIR="s3://${AWS_S3_BUCKET}/${AWS_S3_PROJECT_DIR}/current"
  cd ..
  aws s3 sync ${DOCKER_ARTIFACT_SUBDIR} ${VERSION_DIR}
  aws s3 rm --recursive ${CURRENT_DIR}
  aws s3 cp --recursive ${VERSION_DIR} ${CURRENT_DIR}
fi
if [ -n "${TARGET_CNAME}" ]; then
  AWS_CLOUDFRONT_DISTRIBUTION_ID="$(aws cloudfront list-distributions --query "DistributionList.Items[?Aliases.Items && contains(Aliases.Items, '${TARGET_CNAME}')].Id" --output text)"
  aws cloudfront create-invalidation --distribution-id ${AWS_CLOUDFRONT_DISTRIBUTION_ID} --paths "/*"
fi
