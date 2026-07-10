#!/usr/bin/env bash
#
# Deploys the Lalamove Same Day Delivery functions.
#
# Prereqs (one-time): create the Secret Manager secrets these functions bind:
#   firebase functions:secrets:set LALAMOVE_API_KEY
#   firebase functions:secrets:set LALAMOVE_API_SECRET
#   firebase functions:secrets:set GOOGLE_MAPS_API_KEY   # Geocoding API only
#
# The functions/ predeploy hook runs `npm run build` automatically.
set -euo pipefail

cd "$(dirname "$0")"

firebase deploy --only functions:calculateLalamoveQuote,functions:bookLalamoveDelivery,functions:lalamoveWebhook
