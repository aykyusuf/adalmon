#!/bin/sh
# Config/Identity.xcconfig (+ yerel Config/Identity.local.xcconfig) değerlerinden Swift sabitlerini üretir.
# xcodegen `preGenCommand` olarak çalıştırır; çıktı Sources/Identity/Identity.generated.swift (gitignored).
set -eu
cd "$(dirname "$0")/.."
team=""; prefix=""
for f in Config/Identity.xcconfig Config/Identity.local.xcconfig; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    case "$line" in
      ADALMON_TEAM_ID*=*) team=$(printf '%s' "${line#*=}" | sed 's://.*$::; s/[[:space:]]//g') ;;
      ADALMON_BUNDLE_PREFIX*=*) prefix=$(printf '%s' "${line#*=}" | sed 's://.*$::; s/[[:space:]]//g') ;;
    esac
  done < "$f"
done
[ -n "$prefix" ] || prefix="com.example"
mkdir -p Sources/Identity
cat > Sources/Identity/Identity.generated.swift <<SWIFT
// Otomatik üretilir (tools/gen-identity.sh); gitignored. Değerler Config/Identity*.xcconfig dosyalarından gelir.
enum AdalmonIdentity {
    static let teamID = "$team"
    static let bundlePrefix = "$prefix"
    static let appBundleID = "$prefix.adalmon"
    static let filterBundleID = "$prefix.adalmon.filter"
    static let saverBundleID = "$prefix.adalmon.saver"
    static let appGroupID = "$team.$prefix.adalmon"
    static let machServiceName = "$team.$prefix.adalmon.filter"
}
SWIFT
