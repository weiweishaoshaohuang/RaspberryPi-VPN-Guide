#!/usr/bin/env bash
# SSH security hardening for Ubuntu Server 24.04 on Raspberry Pi 4
#
# What this script does:
#   1. Updates system packages
#   2. Disables password authentication (blocks brute-force attacks)
#   3. Enables public key authentication
#   4. Patches BOTH /etc/ssh/sshd_config AND /etc/ssh/sshd_config.d/*.conf
#      (Ubuntu 24.04 moved cloud-init defaults into sshd_config.d, which
#       takes precedence over the base sshd_config — both must be patched)
#   5. Validates and restarts SSH
#
# Prerequisites: your public key must already be in ~/.ssh/authorized_keys
#   Windows: type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh USER@PI_IP \
#            "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
#
# Usage: sudo bash setup_security.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Pre-flight ─────────────────────────────────────────────────────────────────

[[ $EUID -ne 0 ]] && error "Run as root: sudo bash $0"

# Guard: refuse to disable password auth if no authorized_keys exists anywhere
AUTH_KEYS_FOUND=$(find /home /root -name authorized_keys 2>/dev/null | head -1)
if [[ -z "$AUTH_KEYS_FOUND" ]]; then
    warn "No authorized_keys found on this system!"
    warn "You WILL be locked out if you continue."
    read -rp "Type 'yes' to proceed anyway: " CONFIRM
    [[ "$CONFIRM" != "yes" ]] && error "Aborted. Upload your public key first."
fi

# ── Step 1: System update ──────────────────────────────────────────────────────

info "Updating system packages..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
info "System up to date."

# ── Step 2: Helper — apply a setting in an sshd config file ───────────────────
# Replaces existing (commented or not) lines, or appends if absent. Idempotent.

apply_setting() {
    local key="$1" value="$2" file="$3"
    if grep -qE "^#?[[:space:]]*${key}[[:space:]]" "$file"; then
        sed -i -E "s|^#?[[:space:]]*${key}[[:space:]].*|${key} ${value}|" "$file"
    else
        echo "${key} ${value}" >> "$file"
    fi
}

# ── Step 3: Patch /etc/ssh/sshd_config ────────────────────────────────────────

SSHD_MAIN="/etc/ssh/sshd_config"
info "Patching $SSHD_MAIN..."
cp "$SSHD_MAIN" "${SSHD_MAIN}.bak.$(date +%Y%m%d%H%M%S)"

apply_setting "PasswordAuthentication" "no"  "$SSHD_MAIN"
apply_setting "PubkeyAuthentication"   "yes" "$SSHD_MAIN"
apply_setting "PermitRootLogin"        "no"  "$SSHD_MAIN"

# ── Step 4: Patch /etc/ssh/sshd_config.d/*.conf ───────────────────────────────
# Ubuntu 24.04: 50-cloud-init.conf in this directory overrides the base config.

CONF_DIR="/etc/ssh/sshd_config.d"
if [[ -d "$CONF_DIR" ]]; then
    for conf in "$CONF_DIR"/*.conf; do
        [[ -f "$conf" ]] || continue
        info "Patching override file: $conf"
        cp "$conf" "${conf}.bak.$(date +%Y%m%d%H%M%S)"
        apply_setting "PasswordAuthentication" "no" "$conf"
    done
else
    info "No sshd_config.d directory found — skipping."
fi

# ── Step 5: Validate config syntax ────────────────────────────────────────────

info "Validating SSH configuration syntax..."
sshd -t || error "Config validation failed. Restore from .bak files and retry."

# ── Step 6: Restart SSH ────────────────────────────────────────────────────────

info "Restarting SSH service..."
systemctl restart ssh
info "SSH service restarted."

# ── Done ───────────────────────────────────────────────────────────────────────

echo ""
info "✅ SSH hardening complete."
echo ""
echo "  Verify in a NEW terminal (keep this session open as fallback):"
echo ""
echo "    # Should succeed with key:"
echo "    ssh YOUR_USERNAME@YOUR_PI_LOCAL_IP"
echo ""
echo "    # Should be rejected:"
echo "    ssh -o PubkeyAuthentication=no YOUR_USERNAME@YOUR_PI_LOCAL_IP"
echo "    Expected: Permission denied (publickey)."
echo ""
echo "  Then configure router Port Forwarding:"
echo "    External 22222 → Internal YOUR_PI_LOCAL_IP:22"
echo "    External 443   → Internal YOUR_PI_LOCAL_IP:443"
