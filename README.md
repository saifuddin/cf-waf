# Cloudflare WAF IP Auto-Updater

## Overview

This project provides a script (`update_cf_rule_ip.sh`) that automatically updates a Cloudflare WAF (Web Application Firewall) **custom rule** to allow traffic from the pitchIN office's **current public IP addresses** (both IPv4 and IPv6).

**Why do we need this:**
- This allows machines that are in the pitchIN's office to access *pitchin.dev* domain (i.e. Staging and UAT env), without installing the VPN

**What's been done:**
- Bash script `update_cf_rule_ip.sh` for automated WAF rule updates
- **Dual-stack support**: Automatically detects and includes both IPv4 and IPv6 addresses
- **Cloudflare as source of truth**: Prevents drift by comparing against actual Cloudflare rules, not just local cache
- **Dry run mode**: Test changes before applying them with `--dry-run` flag
- Logging with timestamps (local timezone)
- Graceful handling when the machine is offline or IPv6 is unavailable
- A configuration file (`cloudflare_rule.conf`) to store sensitive details (API token, zone ID, rule ID, etc.)
- An example configuration file (`cloudflare_rule.example.conf`) for guidance
- Caching of the **last known IPs** in `last_ip.txt` to avoid redundant API calls

---

## Installation

1. **Clone or copy this repository** to your machine.

2. **Ensure required dependencies are installed:**
   - `curl` (for fetching public IP and API calls)
   - `jq` (for parsing API responses)

3. **Set execute permissions for the script:**
   ```bash
   chmod +x update_cf_rule_ip.sh
   ```

4. **Create your configuration file:**
   ```bash
   cp cloudflare_rule.example.conf cloudflare_rule.conf
   ```

5. **Edit `cloudflare_rule.conf`** and fill in your Cloudflare credentials:
   - `CF_AUTH_TOKEN`: Your Cloudflare API token with permissions to edit WAF rules
   - `ZONE_ID`: Your Cloudflare zone ID
   - `RULESET_ID`: The ruleset ID containing your WAF rule
   - `RULE_ID`: The specific rule ID to update
   - `FIXED_IPS`: Array of static IPs that should always be in the allowlist

---

## Usage

### Normal Mode (Update Cloudflare)
Run the script to update your Cloudflare WAF rule:
```bash
./update_cf_rule_ip.sh
```

This will:
1. Fetch your current IPv4 address (and IPv6 if available)
2. Check if IPs have changed from the cached values in `last_ip.txt`
3. If changed, fetch the current Cloudflare rule to verify state
4. Compare the new expression with Cloudflare's current expression
5. Update Cloudflare only if the rule needs changing
6. Update the cache file with current IPs

### Dry Run Mode (Test Without Changes)
Test the script without making any changes to Cloudflare:
```bash
./update_cf_rule_ip.sh --dry-run
# or
./update_cf_rule_ip.sh -d
```

This will:
- ✅ Fetch current IPs
- ✅ Show current Cloudflare rule state
- ✅ Display what changes would be made
- ❌ NOT update Cloudflare
- ❌ NOT update the cache file

Use dry run mode to verify the script works correctly before running it for real.

### Automated Execution (Cron Job)
To automatically update the rule every 5 minutes, add this to your crontab:
```bash
*/5 * * * * /path/to/update_cf_rule_ip.sh >> /path/to/update_cf_rule_ip.log 2>&1
```

---

## Features

### IPv4 and IPv6 Support
- Automatically detects both IPv4 and IPv6 addresses
- Includes both in the Cloudflare WAF rule when available
- Rule description shows both IPs: `Block all except Office IP & VPN (24.11.208.217 / 2001:db8::1)`
- Gracefully handles networks without IPv6 connectivity
- Prevents duplicate IPs if IPv6 returns the same address as IPv4

### Drift Prevention (Cloudflare as Source of Truth)
The script uses **Cloudflare as the source of truth** instead of relying solely on `last_ip.txt`:

**How it works:**
1. Quick check: Compare current IPs with `last_ip.txt`
2. If different: Fetch the actual Cloudflare rule via API
3. Compare new expression with Cloudflare's current expression
4. Only update if they differ

**Benefits:**
- ✅ Prevents issues if `last_ip.txt` becomes stale or corrupted
- ✅ Won't make unnecessary updates if someone manually changed the Cloudflare rule
- ✅ Cache file gets corrected automatically if it drifts from reality
- ✅ Still optimizes API calls by using cache when IPs haven't changed

### Storage Format
The `last_ip.txt` file stores both IPs in comma-separated format:
```
24.11.208.217,2001:0db8:85a3::8a2e:0370:7334
```

If IPv6 is unavailable:
```
24.11.208.217,
```

---

## Logging

All actions are logged to `update_cf_rule_ip.log` with timestamps. Example log output:

```
[2025-10-26 17:20:57 CDT] =========================================
[2025-10-26 17:20:57 CDT] DRY RUN MODE - No changes will be made
[2025-10-26 17:20:57 CDT] =========================================
[2025-10-26 17:20:57 CDT] Current IPv4: 24.11.208.217
[2025-10-26 17:20:57 CDT] IPv6 not available on this network
[2025-10-26 17:20:57 CDT] Fetching current Cloudflare ruleset to verify state...
[2025-10-26 17:20:58 CDT] Current Cloudflare expression: (not ip.src in {10.0.0.1})
[2025-10-26 17:20:58 CDT] Cloudflare rule needs update.
[2025-10-26 17:20:58 CDT] New expression: (not ip.src in {10.0.0.1 24.11.208.217})
[2025-10-26 17:20:58 CDT] DRY RUN: Would update rule with:
[2025-10-26 17:20:58 CDT]   Description: Block all except Office IP & VPN (24.11.208.217)
```

---

## Troubleshooting

**IPv6 returns the same address as IPv4:**
- This is normal - the script automatically detects and ignores duplicate IPs
- IPv6 will be marked as unavailable in logs

**Script fails with API authentication error:**
- Verify your `CF_AUTH_TOKEN` has the correct permissions
- Ensure `ZONE_ID`, `RULESET_ID`, and `RULE_ID` are correct

**Cloudflare rule not found:**
- Check that the `RULE_ID` exists in the specified `RULESET_ID`
- Use Cloudflare dashboard or API to verify IDs

**Cache file out of sync:**
- No problem! The script now uses Cloudflare as source of truth
- The cache will be automatically corrected on next run

**Need to test without making changes:**
- Use the dry run mode: `./update_cf_rule_ip.sh --dry-run`
