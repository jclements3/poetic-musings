# ad-lab — a real Active Directory domain, no Windows license required

A genuine Active Directory Domain Controller — real Kerberos KDC, real
LDAP directory, real DNS, real SYSVOL/GPO storage — running as a Samba4
AD DC in a container. Not a mock, not a diagram: every claim below was
verified against the running service, the same way every other piece of
this repo's DevSecOps work was verified.

## Why Samba4, not a real Windows Server

This session runs in a Linux (WSL2) shell with no GUI and no way to
legally obtain a Windows Server license/ISO on your behalf. Samba4's AD
DC implementation is open source, requires no license, and is
wire-compatible with real Windows clients — a genuine Windows machine
can join this domain, authenticate against it, and pull GPOs from it,
exactly as it would against a real Windows Server DC. What it does
*not* give you is a Windows admin experience: authoring GPO policy
*settings* (not just the GPO object) normally happens in the Group
Policy Management Console on a Windows admin workstation with RSAT —
see "Honest gaps" below.

## What's real here

- **Domain**: `poeticmusings.lab` (NetBIOS `POETICM`), forest and domain
  both provisioned for real via `samba-tool domain provision`.
- **Users**: `Administrator`, `krbtgt`, `Guest` (built-in), plus a real
  named user `jclements` created in `OU=IT`.
- **Groups**: `DevSecOps-Admins` (OU=IT), `Platform-Team`
  (OU=Engineering) — `jclements` is a real member of `DevSecOps-Admins`.
- **GPO**: `Password-Policy-Baseline`, a real GPO object created via
  `samba-tool gpo create`, stored in real SYSVOL, linked to `OU=IT` via
  `samba-tool gpo setlink` — confirmed with `samba-tool gpo getlink`.
- **Kerberos**: verified with a real `kinit jclements@POETICMUSINGS.LAB`
  against the password actually set, producing a real TGT
  (`krbtgt/POETICMUSINGS.LAB@POETICMUSINGS.LAB`) with real expiry times,
  confirmed with `klist`.
- **DNS**: Samba's internal DNS backend serves the domain's own zone —
  confirmed externally with `dig @127.0.0.1 -p 8053
  dc1.poeticmusings.lab A` (resolves) and `dig ... _ldap._tcp
  SRV` (resolves the DC-discovery record a real client uses).
- **Network reachability**: Kerberos (88) and LDAP (389) confirmed
  reachable from outside the container on their mapped ports.

## Running it

```
cd ad-lab
docker build -t poeticmusings-ad-dc .
docker run -d --name ad-dc --hostname dc1 \
  -e AD_ADMIN_PASSWORD='<choose a real password>' \
  -e AD_USER_PASSWORD='<choose a real password>' \
  -p 8053:53/tcp -p 8053:53/udp -p 8088:88/tcp -p 8389:389/tcp \
  -p 8445:445/tcp -p 8636:636/tcp \
  poeticmusings-ad-dc
```

First run provisions the domain and seeds the OUs/groups/user/GPO
(takes ~15s); subsequent starts detect the existing domain and skip
straight to starting the service.

Verify it yourself:

```
docker exec ad-dc samba-tool domain info 127.0.0.1
docker exec ad-dc samba-tool user list
docker exec ad-dc samba-tool gpo listall
docker exec ad-dc bash -c "echo '<the password>' | kinit jclements@POETICMUSINGS.LAB"
docker exec ad-dc klist
```

Tear down: `docker rm -f ad-dc`

## Two real bugs hit and fixed while building this

1. **SYSVOL provisioning failed** with
   `set_nt_acl_no_snum ... NT_STATUS_ACCESS_DENIED`. Docker's overlay
   filesystem (and WSL2's backing store under it) doesn't reliably
   support the filesystem extended attributes Samba normally uses to
   store NT ACLs on SYSVOL. Fixed with the documented workaround:
   `--option="posix:eadb=/var/lib/samba/private/eadb.tdb"` on
   `domain provision`, which makes Samba emulate those ACLs via a TDB
   database instead of real xattrs.
2. **`samba-tool gpo create` failed** with `The object name is not
   found` (`net.finddc` couldn't resolve the realm), because `gpo`
   commands do a DNS SRV lookup for the domain and the container's
   `/etc/resolv.conf` still pointed at Docker's default resolver, which
   has never heard of `poeticmusings.lab`. Fixed by pointing
   `/etc/resolv.conf` at `127.0.0.1` (Samba's own internal DNS) once
   the service was up, before seeding any GPO objects. A related,
   separate fix: `gpo create`/`setlink` also need an explicit
   `-U Administrator --password=...` — the OU/group/user creation
   commands succeeded via samba-tool's implicit local-admin access, but
   the `CN=Policies,CN=System` container has stricter ACLs that
   required real, explicit Administrator credentials.

## Honest gaps

- **No domain-joined Windows client.** This proves the AD DC side
  completely — real domain, real Kerberos, real GPO object linked to a
  real OU — but nothing here has joined an actual Windows machine to
  it, so GPO *application* (a client actually pulling and enforcing the
  policy) has not been demonstrated, only GPO *object creation and
  linkage*. Closing this fully needs a real or lab Windows client VM
  joined to `poeticmusings.lab`, which needs a GUI/hypervisor this
  session doesn't have.
- **No policy settings authored inside the GPO.** `Password-Policy-Baseline`
  exists and is linked, but its actual `registry.pol` content is empty
  — authoring real settings (password complexity, lockout thresholds,
  screen-lock timeout) is normally done with GPMC from a Windows admin
  workstation with RSAT installed.
- **No MECM/SCCM or Intune.** Those manage endpoints at fleet scale on
  top of an AD/Entra identity foundation; this lab only provides that
  foundation.
- **Single DC, no replication topology.** A real environment usually
  runs 2+ DCs for redundancy; this is one DC, enough to prove the
  mechanism, not a production topology.
