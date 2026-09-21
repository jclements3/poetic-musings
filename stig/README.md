# DISA STIG scan — a real, scored OpenSCAP run

Not a claim of alignment "by construction" — this is an actual `oscap` XCCDF
evaluation against a real RHEL 8 filesystem, using DISA's own published STIG
profile, with real PASS/FAIL/N/A counts. This closes a gap distinct from
[`k8s/cis-benchmark/`](../k8s/cis-benchmark/README.md): CIS Benchmark and
DISA STIG are related but different standards — CIS is a vendor-neutral
industry baseline; STIG is the specific DoD-mandated standard this repo's
target job posting calls out by name ("STIG evaluation, analysis, and
implementation").

## What ran

- **Scanner**: `oscap` (OpenSCAP) 1.3.9, from Ubuntu 24.04's `openscap-scanner`
  package.
- **Content**: DISA's own SCAP Security Guide (SSG) content for RHEL 8,
  `ssg-rhel8-ds.xml`, profile `xccdf_org.ssgproject.content_profile_stig`
  ("DISA STIG for Red Hat Enterprise Linux 8") — this is the real,
  DISA-aligned XCCDF/OVAL content shipped via Ubuntu's `ssg-nondebian`
  package, not hand-written or fabricated.
- **Target**: `registry.access.redhat.com/ubi8/ubi:latest` (Red Hat
  Universal Base Image 8.10, "Ootpa") — a genuine RHEL 8 filesystem, no
  subscription required. Exported with `docker export`, extracted to a
  local directory, and scanned offline via `OSCAP_PROBE_ROOT` pointed at
  that filesystem (this version of `oscap` has no `--chroot` flag; probing
  an offline root via the `OSCAP_PROBE_ROOT` environment variable is the
  documented equivalent).

## Result

```
   67 PASS
   51 FAIL
  286 notapplicable
    5 notchecked
 1163 notselected  (rules belonging to OTHER profiles in the same
                     datastream — CIS, PCI-DSS, etc. — not part of
                     the STIG profile actually evaluated here)
----
  409 rules actually in scope for the STIG profile (67+51+286+5)
```

Full machine-readable results: [`scap-results.xml.gz`](scap-results.xml.gz)
(gzipped — 17MB raw, 1.3MB compressed). Full human-readable report:
[`scap-report.html`](scap-report.html) (self-contained, includes every
rule's DISA rationale text — open directly in a browser). List of the 51
failing rule IDs: [`fail-rules.txt`](fail-rules.txt).

## Honest read of the FAILs

All 51 failures are genuine gaps in an **unconfigured base container
image** — UBI8 ships as a minimal, unopinionated RHEL userspace; it
deliberately does not pre-apply DoD password/crypto policy, because that's
a site-specific hardening decision, not something a base OS image vendor
bakes in. The failing categories:

- **Password/account policy** (`pam_faillock`, `pam_pwhistory`,
  `pam_pwquality` — `dcredit`/`lcredit`/`minclass`/`maxrepeat`/etc.): no
  PAM password-complexity or lockout policy configured — this is exactly
  the kind of setting a real STIG remediation pass applies via
  `authselect`/`pam_pwquality`, not something a container base image ships
  pre-configured.
- **Crypto policy** (`configure_crypto_policy`, SSH cipher/MAC hardening):
  RHEL's system-wide crypto policy is left at its default, not set to
  `FIPS`/`DISA_STIG` — a real remediation would set
  `update-crypto-policies --set DISA_STIG`.
- **RPM integrity** (`rpm_verify_hashes`, `rpm_verify_ownership`,
  `gpgcheck_local_packages`): package-manager-level integrity checks not
  enforced by default.
- **`prefer_64bit_os`**: a single informational/architecture check.

None of these are a flaw in this repo — they're the accurate, unremediated
state of a stock base image, which is the correct baseline to show before
remediation. A next step (not done here, named honestly as a gap) would be
to actually apply STIG remediation (either `oscap xccdf eval --remediate`,
or an Ansible role using the SSG-published remediation playbooks) and
re-scan to show the FAIL count drop — the same before/after pattern a real
DevSecOps STIG compliance pipeline runs.

## Two real snags hit while building this

1. **`openscap-scanner` doesn't exist as a package name on Ubuntu 22.04** —
   only on 24.04 (`noble`); on 22.04 (`jammy`) the `oscap` binary ships
   inside `libopenscap8` itself. Worked around by using an Ubuntu 24.04
   container as the scanner host.
2. **No official DISA STIG SCAP content exists for Ubuntu** — Canonical's
   SSG packages (`ssg-debderived`) only ship **CIS** profiles for Ubuntu,
   not STIG; DISA's actual published STIG content targets RHEL family
   distros. Rather than mislabel a CIS-Ubuntu scan as "STIG," this scan
   targets a real RHEL 8 filesystem (UBI8) with DISA's own RHEL8 STIG
   content — the only way to run a genuine, correctly-labeled DISA STIG
   evaluation in this environment.
3. **`oscap xccdf eval` in this openscap version has no `--chroot` flag**
   (that's a newer CLI addition) — the offline-root equivalent for this
   version is the `OSCAP_PROBE_ROOT` environment variable, pointed at the
   exported/extracted UBI8 filesystem.

## Honest gaps

- **No remediation applied.** This scan shows the *unremediated* baseline
  state only — no `--remediate` run, no before/after comparison. That's
  the natural next step, not done here.
- **Container filesystem, not a running/booted RHEL host.** Some rules
  that depend on live system state (running services, kernel boot
  parameters) return `notapplicable` or `notchecked` against a static,
  offline filesystem rather than a booted machine — an accurate limitation
  of scanning a container export rather than a real VM/bare-metal host.
- **RHEL content against a container base image, not this repo's own
  containers.** This repo's actual application containers
  (`app/status-service`, `ad-lab/`) are Debian/Ubuntu-based, which has no
  official DISA STIG content — hence scanning UBI8 as the closest
  available *correctly-labeled* DISA STIG target, clearly distinct from
  (and complementary to) the CIS Benchmark run in
  [`k8s/cis-benchmark/`](../k8s/cis-benchmark/README.md), which does scan
  this repo's own live cluster.
