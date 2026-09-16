#!/usr/bin/env bash
# Compatibility notice for the retired source-overlay workflow.
printf '%s\n' "Patch export is retired. Commit and publish engine changes to https://github.com/chrissotraidis/strikers, then update ENGINE_PIN and ENGINE_SOURCE_TREE in scripts/native/common.sh and the dependency manifest." >&2
exit 1
