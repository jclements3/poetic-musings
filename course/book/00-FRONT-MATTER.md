# The Wheel

### What Does Not Need To Be Reinvented

*A complete DevSecOps study book — the 9 zones, real evidence, and a
toolkit — built for the GMD DevSecOps Engineer role (Valkyrie Enterprises,
Job ID 4472), and for every project after it.*

---

## How to use this book

This book has three layers, and they're meant to be read in a specific
order depending on what you need at the moment:

1. **The nine zone chapters** (1-9) are the *teaching* layer. Each one
   stands alone — read them in order once, front to back, to build the
   full mental model; come back to any single one later as a reference
   when you need to go deep on just that zone.
2. **The appendix, "The Wheel"** is the *toolkit* layer — real, working,
   point-free Python recipes built on `playbook/haskell.py`, organized by
   zone, meant to be copied and adapted rather than written from scratch
   the next time you need a small script to parse something, gate
   something, or triage something.
3. **This book itself lives inside a real, working portfolio repo**
   (`poetic-musings`) that you can open alongside any chapter and see the
   actual files, actual command output, and actual bugs-hit-and-fixed
   behind every claim. Nothing in here is theoretical unless the chapter
   says so explicitly.

Every chapter follows the same honest discipline this whole repo is built
on: **real commands and real numbers where they exist, gaps named
plainly, nothing claimed as "verified" that wasn't actually verified.**
Where a topic is genuinely course knowledge rather than something proven
in this repo (SonarQube, Nexus, Azure DevOps, ELK, HashiCorp Vault, Istio),
every chapter says so explicitly, at the point where it comes up — not
buried in a footnote. You should walk into an interview or a first week
on the job able to say, precisely, "this I've built and verified myself,
this I understand and can speak to but haven't hands-on-proven yet" — and
mean it, for every single tool in this book.

---

## Day One at Valkyrie — Orientation

You are the **GMD DevSecOps Engineer**, supporting GM's Digital
Acquisition & Infrastructure team, architecting and scaling the DevSecOps
environment inside the Integrated Digital Data Environment (IDDE). This
section is the condensed version of everything below: what's actually
proven, what to do first, and where to look when something breaks.

### What you're walking in with (the honest inventory)

Quoting the real, current summary from this repo's own dashboard
(`JOB.html`), unedited:

> This sprint cycle, the DevSecOps effort has delivered verified
> capability across all required areas: **1) Infrastructure as Code
> (Terraform)** — full environments stand up from code in minutes,
> verified against a live AWS account; **2) Container orchestration
> (Kubernetes)** — hardened to the restricted standard, no root,
> default-deny networking, 62 benchmark checks passed; **3) CI/CD
> automation (GitHub Actions, GitLab CI, Jenkins)** — same pipeline in
> three vendors, caught a live dependency vulnerability on first run and a
> real Terraform misconfiguration on Jenkins; **4) Hybrid cloud (AWS,
> Azure)** — AWS proven end-to-end, Azure built to identical standard;
> **5) Identity & directory services (Samba4 AD)** — real domain stood
> up, verified by live login and credential pull; **6) Compliance &
> hardening (DISA STIG)** — scored DoD baseline, 67 pass / 51 fail of 409
> rules, each traceable; **7) Pipeline security scanning (SAST, SCA,
> container/IaC scans)** — seven layered scans on every change, caught
> real vulnerabilities including in the base image; **8) Developer
> environments (Coder)** — server deployed live and healthy; **9)
> Configuration management (Ansible)** — idempotence proven cold: one run
> to correct, zero on rerun.

**Named, not hidden, remaining gaps:** live Azure apply, Azure DevOps
pipelines, a Windows client + SCCM, STIG remediation (the baseline is
scored, the fixes aren't applied yet), and Coder workspace templates. Plus
course-only knowledge you should brush up but haven't hands-on-proven:
SonarQube, Nexus, ELK, HashiCorp Vault, Istio service mesh.

This is not a weakness to hide in an interview or on the job — it's
exactly the kind of precise, falsifiable inventory a DevSecOps engineer is
supposed to be able to produce about *any* environment they inherit,
including someone else's. Practicing it on your own portfolio first is
the whole point.

### Week One: Evaluate, Set Up, Do the Job

A concrete, zone-by-zone first-week sequence. Each item points to the
chapter that teaches the "how":

1. **Evaluate the situation** (Zones 1, 8, 9 — Chapters 1, 8, 9): find
   every pipeline file, every scan gate, every dashboard that already
   exists before you touch anything. Read `freshness.py`'s pattern
   (Appendix B.7) and ask "when did each of these last actually run
   successfully" before trusting any of it. Ask for the current waiver
   ledger and check for silently-expired entries (Appendix B.5, Chapter
   9 §4).
2. **Set things up** (Zones 2, 6 — Chapters 2, 6): get a working
   development environment (Coder or equivalent) and confirm your own
   `terraform plan` / `ansible-playbook --check` run clean against the
   current state before you change anything — drift you didn't cause is
   not drift you want to be blamed for.
3. **Do the job** (Zones 3, 4, 5, 7 — Chapters 3, 5, 7): ship changes
   through the same gated pipeline everyone else does, never around it.
   Know the CI/CD dialect(s) in actual use (this book covers all four:
   GitHub Actions, GitLab CI, Jenkins, Azure DevOps) and the full 7-gate
   security scanning stack cold.
4. **Fix things / troubleshoot** (Zone 8 — Chapter 8): when something
   breaks, the four-question triage framework in Chapter 8 §6 (Blast
   radius → What changed → Which layer → Fastest safe rollback) is not
   optional reading — it is the fastest path back to a working system
   under pressure, and it's already fully worked out. Use it.
5. **Accomplish your duties, provably** (Zone 9 — Chapter 9): every
   control you implement needs evidence an auditor can find without
   asking you. STIG scans, SBOMs, waiver expiries — if it isn't archived
   and retrievable, it didn't happen, no matter how sure you are that it
   did.

### The one thing to internalize before anything else

**A gate that cannot fail is decoration.** Every real control in this
book — every scanner, every policy check, every pipeline stage — was
proven to actually catch something before it was trusted. Chapter 3 §8
covers this directly (the "dirty-fixture regression" principle), and it
should become a reflex: the first time you stand up a new check anywhere,
prove it can say no before you believe it when it says yes.

---

## Table of Contents

| # | Zone | Chapter |
|---|---|---|
| — | Front Matter & Day One Orientation | this file |
| 1 | Plan & Source | `chapter-01-plan-and-source.md` |
| 2 | Develop | `chapter-02-develop.md` |
| 3/4 | Build & Test | `chapter-03-build-and-test.md` |
| 5 | Secure | `chapter-05-secure.md` |
| 6 | Provision | `chapter-06-provision.md` |
| 7 | Deploy & Orchestrate | `chapter-07-deploy-and-orchestrate.md` |
| 8 | Operate & Observe (+ full triage framework) | `chapter-08-operate-and-observe.md` |
| 9 | Evidence & Govern | `chapter-09-evidence-and-govern.md` |
| A | Appendix — The Wheel (toolkit) | `APPENDIX-TOOLKIT.md` |
