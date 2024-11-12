#!/bin/bash

#
# Detects the target cloud provider based on the repo name and checks for the associated credentials.
#
function check_cloud_provider_creds() {
  if [[ "$REPO_NAME" == *"-aws-"* ]]; then
    if [[ -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" ]]; then
      echo " - AWS detected and credentials found"
      return 0
    fi
  elif [[ "$REPO_NAME" == *"-gcp-"* ]]; then
    if [[ -n "$GOOGLE_APPLICATION_CREDENTIALS" && -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
      echo " - GCP detected and credentials found"
      return 0
    fi
  elif [[ "$REPO_NAME" == *"-azurerm-"* || "$REPO_NAME" == *"-azure-"* ]]; then
    if [[ -n "$ARM_CLIENT_ID" && -n "$ARM_CLIENT_SECRET" && -n "$ARM_SUBSCRIPTION_ID" && -n "$ARM_TENANT_ID" ]]; then
      echo " - Azure detected and credentials found"
      return 0
    fi
  fi
  printf "${RED}No valid cloud provider is detected or the associated credentials are missing${NO_COLOR}\n"
  return 1
}
