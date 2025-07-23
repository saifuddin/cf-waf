# Cloudflare WAF IP Auto-Updater

## Overview

This project provides a script (`update_cf_rule_ip.sh`) that automatically updates a Cloudflare WAF (Web Application Firewall) **custom rule** to allow traffic from the pitchIN office's **current public IP address**.

**Why do we need this:**
- This allows machine that's in the pitchIN's office to access *pitchin.dev* domain (i.e. Staging and UAT env), without installing the VPN

**What's been done:**
- Bash script `update_cf_rule_ip.sh` for automated WAF rule updates.
- Logging with timestamps (local timezone).
- Graceful handling when the machine is offline.
- A configuration file (`cloudflare_rule.conf`) to store sensitive details (API token, zone ID, rule ID, etc.).
- An example configuration file (`cloudflare_rule.example.conf`) for guidance.
- Caching of the **last known IP** in `last_ip.txt` to avoid redundant API updates.

---

## Installation

1. **Clone or copy this repository** to your machine.

2. **Ensure required dependencies are installed:**
   - `curl` (for fetching public IP and API calls)
   - `jq` (for parsing API responses)

3. **Set execute permissions for the script:**
   ```bash
   chmod +x update_cf_rule_ip.sh
