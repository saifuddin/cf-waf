#!/bin/bash

# =========================================
# Cloudflare Firewall Rule IP Updater
# =========================================

CONFIG_FILE="$(dirname "$0")/cloudflare_rule.conf"
LOG_FILE="$(dirname "$0")/update_cf_rule_ip.log"
LAST_IP_FILE="$(dirname "$0")/last_ip.txt"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $1" | tee -a "$LOG_FILE"
}

# Ensure configuration file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  log "Error: Configuration file $CONFIG_FILE not found."
  exit 1
fi

# Load configuration
source "$CONFIG_FILE"

# 1. Get the current public IP
CURRENT_IP=$(curl -s --max-time 10 https://api.ipify.org)
if [[ -z "$CURRENT_IP" ]]; then
  log "Error: Unable to retrieve current public IP (offline or network issue)."
  exit 1
fi
log "Current public IP: $CURRENT_IP"

# 2. Check last known IP
if [[ -f "$LAST_IP_FILE" ]]; then
  LAST_IP=$(cat "$LAST_IP_FILE")
  if [[ "$CURRENT_IP" == "$LAST_IP" ]]; then
    log "IP unchanged ($CURRENT_IP). No update needed."
    exit 0
  fi
fi

# 3. Build the new expression
ALL_IPS="${FIXED_IPS[@]} $CURRENT_IP"
EXPRESSION="(not ip.src in {${ALL_IPS// / }})"
log "Updating rule with expression: $EXPRESSION"

# 4. Send the PATCH request to update the firewall rule
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

# 5. Check response success
if echo "$RESPONSE" | jq -e '.success' >/dev/null; then
  log "Firewall rule updated successfully."
  NEW_EXPRESSION=$(echo "$RESPONSE" | jq -r '.result.rules[] | select(.id=="'"$RULE_ID"'") | .expression')
  log "Current rule expression: $NEW_EXPRESSION"
  echo "$CURRENT_IP" > "$LAST_IP_FILE"
else
  log "Failed to update firewall rule."
  log "Response: $RESPONSE"
  exit 1
fi
