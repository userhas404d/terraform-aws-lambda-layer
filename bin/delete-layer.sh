#!/usr/bin/env bash
LAYER_BASE_ARN=$1

echo "delete-layer: deleting layer-name: $LAYER_BASE_ARN"

LAYER_VERSION_RESPONSE=$(aws lambda list-layer-versions --layer-name "$LAYER_BASE_ARN")

readarray -t LAYER_VERSIONS < <(echo "$LAYER_VERSION_RESPONSE" | jq -r '.LayerVersions[].LayerVersionArn')
for LAYER in "${LAYER_VERSIONS[@]}"; do
  aws lambda delete-layer-version \
    --layer-name "$LAYER_BASE_ARN" \
    --version-number "${LAYER#"$LAYER_BASE_ARN:"}"
done
