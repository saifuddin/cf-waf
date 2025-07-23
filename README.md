# Cloudflare WAF IP Auto-Updater

## Overview

This project provides a script (`update_cf_rule_ip.sh`) that automatically updates a Cloudflare WAF (Web Application Firewall) **custom rule** to allow traffic from your **current public IP address**.

**What's been done:**
- Bash script `update_cf_rule_ip.sh` for automated WAF rule updates.
- Logging with timestamps (local timezone).
- Graceful handling when the machine is offline.
- A configuration file (`cloudflare_rule.conf`) to store sensitive details (API token, zone ID, rule ID, etc.).
- An example configuration file (`cloudflare_rule.example.conf`) for guidance.

---

## Installation

1. **Clone or copy this repository** to your machine.

2. **Ensure required dependencies are installed:**
   - `curl` (for fetching public IP and API calls)
   - `jq` (for parsing API responses)
   
   On macOS:
   ```bash
   brew install jq
