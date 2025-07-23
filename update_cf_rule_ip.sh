#!/bin/bash

# =========================================
# Cloudflare Firewall Rule IP Updater
# =========================================

CONFIG_FILE="$(dirname "$0")/cloudflare_rule.conf"
LOG_FILE="$(dirname "$0")/update_cf_rule_ip.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $1" | tee -a "$LOG_FILE"
}

if [[ ! -f "$CONFIG_FILE" ]]; then
  log "Error: Configuration file $CONFIG_FILE not found."
  exit 1
fi

source "$CONFIG_FILE"

CURRENT_IP=$(curl -s --max-time 10 https://api.ipify.org)
if [[ -z "$CURRENT_IP" ]]; then
  log "Error: Unable to retrieve current public IP (offline or network issue)."
  exit 1
fi
log "Current public IP: $CURRENT_IP"

ALL_IPS="${FIXED_IPS[@]} $CURRENT_IP"
EXPRESSION="(not ip.src in {${ALL_IPS// / }})"

log "Updating rule with expression: $EXPRESSION"

RESPONSE=$(curl -s -X PATCH \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$RULESET_ID/rules/$RULE_ID" \
  -H "Authorization: Bearer $CF_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"action\": \"block\",
    \"description\": \"Block all except Office IP & VPN ($CURRENT_IP)\",
    \"enabled\": true,
    \"expression\": \"$EXPRESSION\",
    \"id\": \"$RULE_ID\"
  }")

# Fixed success check
if echo "$RESPONSE" | jq -e '.success' >/dev/null; then
  log "Firewall rule updated successfully."
  log "Current rule expression: $(echo "$RESPONSE" | jq -r '.result.rules[] | select(.id=="'"$RULE_ID"'") | .expression')"
else
  log "Failed to update firewall rule."
  log "Response: $RESPONSE"
  exit 1
fi
