#!/bin/bash
set -euo pipefail

# Runs against a LIVE, already-running DC (unlike provision.sh's domain
# provision, which works directly against the offline database).
# "samba-tool gpo create" specifically needs to resolve a real DC over
# CLDAP and write to SYSVOL over SMB, so it must run after samba is
# actually listening -- running it during offline provisioning fails
# with "The object name is not found" (net.finddc has nothing to find).

MARKER="/var/lib/samba/private/.objects-seeded"
if [ -f "$MARKER" ]; then
  echo "[seed] Objects already seeded, skipping."
  exit 0
fi

echo "[seed] Waiting for the DC to accept LDAP connections..."
for _ in $(seq 1 30); do
  if ldapsearch -x -H ldap://127.0.0.1 -b "" -s base >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "[seed] Creating OUs, groups, a user, and a GPO..."

samba-tool ou create "OU=IT,DC=poeticmusings,DC=lab"
samba-tool ou create "OU=Engineering,DC=poeticmusings,DC=lab"

samba-tool group add "DevSecOps-Admins" --groupou="OU=IT"
samba-tool group add "Platform-Team" --groupou="OU=Engineering"

samba-tool user create jclements "${AD_USER_PASSWORD:-LabUser!2026Change}" \
  --userou="OU=IT" \
  --given-name="James" \
  --surname="Clements" \
  --mail-address="jclements@poeticmusings.lab"
samba-tool group addmembers "DevSecOps-Admins" jclements

# A real GPO object: created and linked to the IT OU, proving the
# AD/GPO *mechanism* end to end (real GPO object in AD, real SYSVOL
# storage, real linkage to an OU) using only CLI tooling on Linux.
# Authoring the policy *settings* inside it (the actual registry.pol
# content -- e.g. password complexity, screen-lock timeout) is normally
# done with the Group Policy Management Console from a Windows admin
# workstation with RSAT installed; that's a genuine, named gap this lab
# doesn't close, since it requires an actual Windows machine, not just
# an AD DC.
# The Policies container has stricter ACLs than the objects created
# above -- those succeeded via samba-tool's implicit local-admin auth,
# but gpo create/setlink need an explicit, real Administrator identity.
ADMIN_PASSWORD="${AD_ADMIN_PASSWORD:?AD_ADMIN_PASSWORD must be set}"
CREATE_OUTPUT=$(samba-tool gpo create "Password-Policy-Baseline" -U Administrator --password="${ADMIN_PASSWORD}")
echo "$CREATE_OUTPUT"
GPO_GUID=$(echo "$CREATE_OUTPUT" | grep -oE '\{[0-9A-Fa-f-]+\}')
echo "[seed] Parsed GPO GUID: ${GPO_GUID}"
samba-tool gpo setlink "OU=IT,DC=poeticmusings,DC=lab" "${GPO_GUID}" -U Administrator --password="${ADMIN_PASSWORD}"

touch "$MARKER"
echo "[seed] Done. GPO ${GPO_GUID} linked to OU=IT."
