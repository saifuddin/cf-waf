#!/bin/bash

# =========================================
# Cloudflare Firewall Rule IP Updater
# =========================================

# Parse command-line arguments
DRY_RUN=false
if [[ "$1" == "--dry-run" || "$1" == "-d" ]]; then
  DRY_RUN=true
fi

CONFIG_FILE="$(dirname "$0")/cloudflare_rule.conf"
LOG_FILE="$(dirname "$0")/update_cf_rule_ip.log"
LAST_IP_FILE="$(dirname "$0")/last_ip.txt"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $1" | tee -a "$LOG_FILE"
}

# Log dry run mode if enabled
if [[ "$DRY_RUN" == true ]]; then
  log "========================================="
  log "DRY RUN MODE - No changes will be made"
  log "========================================="
fi

# Ensure configuration file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  log "Error: Configuration file $CONFIG_FILE not found."
  exit 1
fi

# Load configuration
source "$CONFIG_FILE"

# 1. Get the current public IPs (IPv4 and IPv6)
CURRENT_IPV4=$(curl -4 -s --max-time 10 https://api64.ipify.org)
if [[ -z "$CURRENT_IPV4" ]]; then
  log "Error: Unable to retrieve current IPv4 address (offline or network issue)."
  exit 1
fi
log "Current IPv4: $CURRENT_IPV4"

# Try to get IPv6 (may not be available)
CURRENT_IPV6=$(curl -6 -s --max-time 10 https://api64.ipify.org 2>/dev/null)
if [[ -n "$CURRENT_IPV6" && "$CURRENT_IPV6" != "$CURRENT_IPV4" ]]; then
  log "Current IPv6: $CURRENT_IPV6"
else
  log "IPv6 not available on this network"
  CURRENT_IPV6=""
fi

# 2. Format current IPs for storage
CURRENT_IPS="$CURRENT_IPV4,$CURRENT_IPV6"

# 3. Check last known IPs (optimization to avoid unnecessary API calls)
SHOULD_CHECK_CLOUDFLARE=true
if [[ -f "$LAST_IP_FILE" ]]; then
  LAST_IPS=$(cat "$LAST_IP_FILE")
  if [[ "$CURRENT_IPS" == "$LAST_IPS" ]]; then
    log "IPs unchanged ($CURRENT_IPS). No update needed."
    exit 0
  fi
  log "IPs changed from last known: $LAST_IPS -> $CURRENT_IPS"
fi

# 4. GET current Cloudflare ruleset (source of truth)
log "Fetching current Cloudflare ruleset to verify state..."
CF_RULESET_RESPONSE=$(curl -s -X GET \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$RULESET_ID" \
  -H "Authorization: Bearer $CF_AUTH_TOKEN" \
  -H "Content-Type: application/json")

if ! echo "$CF_RULESET_RESPONSE" | jq -e '.success' >/dev/null; then
  log "Error: Failed to fetch current Cloudflare ruleset."
  log "Response: $CF_RULESET_RESPONSE"
  exit 1
fi

# 5. Extract current expression from Cloudflare for our specific rule
CURRENT_EXPRESSION=$(echo "$CF_RULESET_RESPONSE" | jq -r '.result.rules[] | select(.id=="'"$RULE_ID"'") | .expression')
if [[ -z "$CURRENT_EXPRESSION" || "$CURRENT_EXPRESSION" == "null" ]]; then
  log "Error: Could not find rule with ID $RULE_ID in ruleset"
  exit 1
fi
log "Current Cloudflare expression: $CURRENT_EXPRESSION"

# 6. Build the new expression with both IPv4 and IPv6
# Combine FIXED_IPS with current public IPs
DYNAMIC_IPS="$CURRENT_IPV4"
if [[ -n "$CURRENT_IPV6" ]]; then
  DYNAMIC_IPS="$DYNAMIC_IPS $CURRENT_IPV6"
fi

ALL_IPS="${FIXED_IPS[@]} $DYNAMIC_IPS"
NEW_EXPRESSION="(not ip.src in {${ALL_IPS// / }})"

# 7. Compare expressions to see if update is needed
if [[ "$CURRENT_EXPRESSION" == "$NEW_EXPRESSION" ]]; then
  log "Cloudflare rule already up-to-date."
  if [[ "$DRY_RUN" == false ]]; then
    log "Updating cache file."
    echo "$CURRENT_IPS" > "$LAST_IP_FILE"
  fi
  exit 0
fi

log "Cloudflare rule needs update."
log "Current expression: $CURRENT_EXPRESSION"
log "New expression:     $NEW_EXPRESSION"

# 8. Build description with current IPs
IP_DESCRIPTION="$CURRENT_IPV4"
if [[ -n "$CURRENT_IPV6" ]]; then
  IP_DESCRIPTION="$IP_DESCRIPTION / $CURRENT_IPV6"
fi

# 9. Handle dry run vs. actual update
if [[ "$DRY_RUN" == true ]]; then
  log "========================================="
  log "DRY RUN: Would update rule with:"
  log "  Description: Block all except Office IP & VPN ($IP_DESCRIPTION)"
  log "  Expression:  $NEW_EXPRESSION"
  log "  Action:      block"
  log "  Enabled:     true"
  log "========================================="
  log "DRY RUN: Skipping actual Cloudflare update"
  log "DRY RUN: Skipping cache file update"
  exit 0
fi

# 10. Send the PATCH request to update the firewall rule
log "Sending PATCH request to Cloudflare..."
RESPONSE=$(curl -s -X PATCH \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$RULESET_ID/rules/$RULE_ID" \
  -H "Authorization: Bearer $CF_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"action\": \"block\",
    \"description\": \"Block all except Office IP & VPN ($IP_DESCRIPTION)\",
    \"enabled\": true,
    \"expression\": \"$NEW_EXPRESSION\",
    \"id\": \"$RULE_ID\"
  }")

# 11. Check response success
if echo "$RESPONSE" | jq -e '.success' >/dev/null; then
  log "Firewall rule updated successfully."
  UPDATED_EXPRESSION=$(echo "$RESPONSE" | jq -r '.result.rules[] | select(.id=="'"$RULE_ID"'") | .expression')
  log "Updated rule expression: $UPDATED_EXPRESSION"
  echo "$CURRENT_IPS" > "$LAST_IP_FILE"
  log "Cache file updated with: $CURRENT_IPS"
else
  log "Failed to update firewall rule."
  log "Response: $RESPONSE"
  exit 1
fi
