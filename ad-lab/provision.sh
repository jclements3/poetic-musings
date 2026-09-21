#!/bin/bash
set -euo pipefail

REALM="${AD_REALM:-POETICMUSINGS.LAB}"
DOMAIN="${AD_DOMAIN:-POETICM}"
ADMIN_PASSWORD="${AD_ADMIN_PASSWORD:?AD_ADMIN_PASSWORD must be set}"

SAM_DB="/var/lib/samba/private/sam.ldb"

if [ ! -f "$SAM_DB" ]; then
  echo "[provision] No existing domain found -- provisioning ${REALM} for the first time."

  rm -f /etc/samba/smb.conf

  # --option="posix:eadb=..." makes Samba emulate NT ACLs (needed for
  # SYSVOL/GPO storage) via a TDB database instead of real filesystem
  # extended attributes. Docker's overlay filesystem (and WSL2's backing
  # store under it) doesn't reliably support the xattr operations Samba
  # normally uses for this, which otherwise fails provisioning with
  # "set_nt_acl_no_snum ... NT_STATUS_ACCESS_DENIED" on SYSVOL. This is
  # the standard, documented workaround for containerized Samba AD DCs.
  samba-tool domain provision \
    --realm="${REALM}" \
    --domain="${DOMAIN}" \
    --adminpass="${ADMIN_PASSWORD}" \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --use-rfc2307 \
    --option="posix:eadb=/var/lib/samba/private/eadb.tdb"

  echo "[provision] Domain provisioned."
else
  echo "[provision] Existing domain found at ${SAM_DB} -- skipping provision, starting as-is."
fi
