#!/usr/bin/env bash
#
# Deploys ONLY the functions affected by the JRS shipping fix
# (retry-with-backoff + no silent ₱250 fallback).
#
# It intentionally EXCLUDES the Lalamove functions
# (calculateLalamoveQuote, bookLalamoveDelivery, lalamoveWebhook) because their
# Secret Manager secrets aren't created yet:
#   LALAMOVE_API_KEY, LALAMOVE_API_SECRET, GOOGLE_MAPS_API_KEY
# Deploying them now would 404. Run ./deploy-lalamove.sh later, after setting
# those secrets with `firebase functions:secrets:set <NAME>`.
#
# The functions/ predeploy hook runs `npm run build` automatically.
set -euo pipefail

cd "$(dirname "$0")"

firebase deploy --only \
  functions:calculateJRSShipping,functions:createCheckoutSession,functions:createCodOrder
