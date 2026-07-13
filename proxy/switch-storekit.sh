#!/usr/bin/env bash
#
# Flip the Fil surfacing proxy between DEV and OFFICIAL subscription checking.
#
#   ./switch-storekit.sh dev       # skip Apple verification — test with the local Products.storekit
#   ./switch-storekit.sh official  # real App Store verification — use a sandbox tester
#   ./switch-storekit.sh status    # show which mode the proxy is in
#
# The switch is a single proxy secret, DEV_BYPASS. The app never changes: it always sends the
# transaction id, and the proxy decides whether to trust it. Secure by default — anything other
# than "1" (including unset) means full verification.
set -euo pipefail
cd "$(dirname "$0")"

mode="${1:-status}"
case "$mode" in
  dev)
    printf '1' | npx wrangler secret put DEV_BYPASS
    echo ""
    echo "✅ DEV mode: Apple verification OFF."
    echo "   In Xcode, set the scheme's StoreKit Configuration to Products.storekit, then buy Fil Pro."
    echo "   Fake local purchases will now be accepted by the proxy."
    ;;
  official)
    printf '0' | npx wrangler secret put DEV_BYPASS
    echo ""
    echo "✅ OFFICIAL mode: real App Store verification ON."
    echo "   In Xcode, set the scheme's StoreKit Configuration to None, sign in as a sandbox tester,"
    echo "   then buy Fil Pro. Only Apple-verified subscriptions will be served."
    ;;
  status)
    echo "Proxy secrets (DEV_BYPASS = 1 means DEV mode, anything else means OFFICIAL):"
    npx wrangler secret list
    ;;
  *)
    echo "usage: ./switch-storekit.sh dev | official | status" >&2
    exit 1
    ;;
esac
