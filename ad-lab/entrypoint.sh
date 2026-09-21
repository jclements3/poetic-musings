#!/bin/bash
set -euo pipefail

/provision.sh

echo "[entrypoint] Starting samba (AD DC) in the background to seed objects..."
/usr/sbin/samba --foreground --no-process-group &
SAMBA_PID=$!

# samba-tool gpo (and other commands that resolve a DC via net.finddc)
# do a DNS SRV lookup for the realm, then a CLDAP ping -- which only
# works if this container's resolver actually points at Samba's own
# internal DNS (which owns the poeticmusings.lab zone), not whatever
# Docker's default resolver was pointing at before Samba even existed.
echo "nameserver 127.0.0.1" > /etc/resolv.conf

/seed-objects.sh

echo "[entrypoint] Seeding complete. samba (pid ${SAMBA_PID}) continues in the foreground."
wait "${SAMBA_PID}"
