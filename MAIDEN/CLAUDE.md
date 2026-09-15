# MAIDEN — read this first (Claude Code and humans)

## How this tree got here, and how changes go back

Jim moves this project between his **home laptop** and the **lab computer**
with **Dropbox only — not GitHub**. If you are reading this on the lab
machine, the tree was unpacked from `maiden.tar.bz2` (Dropbox → `MAIDEN`
folder), it has **no `.git` directory**, and that is intentional.

- **Do not** run the `git clone` steps in `LAB-SETUP.md §1` — the tree is
  already here. Start at `LAB-SETUP.md §2` (toolchain) and go on from there.
- **Do not** `git init`, push, or try to reach GitHub. Work directly in the
  unpacked tree.
- **Going back to the home laptop:** when Jim asks to "pack up" / "save to
  Dropbox", rebuild the tarball from the repo's parent directory and put it
  in the Dropbox `MAIDEN` folder, replacing the old one with a new date:

  ```bash
  cd <parent of maiden>
  tar -cjf maiden.tar.bz2 \
    --exclude='maiden/.venv' --exclude='maiden/.git' --exclude='maiden/.claude' \
    --exclude='**/.git' --exclude='**/dist-newstyle' --exclude='**/__pycache__' \
    --exclude='*.pyc' --exclude='maiden/upload' --exclude='maiden/mat-*.png' \
    --exclude='maiden/firmware/doppler/build/doppler_top.json' \
    maiden
  cp maiden.tar.bz2 "<Dropbox>/MAIDEN/MAIDEN-snapshot-$(date +%F).tar.bz2"
  ```

  Then delete the older snapshot in that folder. **One snapshot file in
  Dropbox/MAIDEN, ever.** Do not add loose copies, packages, or extras —
  that caused real confusion on 28 Aug 2026.

- **Receiving a snapshot from the other machine** (either direction): do
  not extract on top of the working tree blindly. Unpack to a scratch
  directory, then sync it over, keeping this machine's `.git`, `.venv`, and
  build outputs:

  ```bash
  mkdir -p /tmp/incoming && tar -xjf "<Dropbox>/MAIDEN/MAIDEN-snapshot-<date>.tar.bz2" -C /tmp/incoming
  rsync -av --exclude='.git' --exclude='.venv' --exclude='dist-newstyle' \
        /tmp/incoming/maiden/ <path-to>/maiden/
  ```

  Show Jim what changed (`rsync` prints it; at home `git status` shows the
  tracked side). Whichever machine last packed up is the source of truth —
  Jim works on one machine at a time, so there should be no merges. If
  `finance/` came back, re-run the Tackler balance before trusting totals.

- **Round trip in one line:** lab → "pack up to Dropbox" → home → "bring in
  the Dropbox snapshot" → work → "pack up to Dropbox" → lab. Same words,
  same file, same folder.

## What is private (never goes to the public GitHub repo)

The GitHub repo is public. These are gitignored and travel **only** in the
tarball: `MAIDEN-*` (whitepaper `.tex`/`.pdf`, briefing `.pptx`,
spreadsheets), `figures/i*/`, `LEDGER.md`, `finance/` (Tackler books +
receipts), `tabletop-range-BOM-plan.md`, `hardware/launcher-catcher.md`,
`HANDOFF.md`, logos. Never quote dollar amounts or vendor names into
anything that might be pushed.

## Where things are

| Need | File |
|---|---|
| Lab-machine setup + arrival-day flashing | `LAB-SETUP.md`, `theremin/clash/bringup/BRINGUP.md` |
| Sprint status / what's done | `course/maiden00.md` §Status |
| Whitepaper source of record | `MAIDEN-*-white-paper.tex` (build: `pdflatex` ×2) |
| Briefing | `MAIDEN-Tabletop-*-2026.pptx` (edit in PowerPoint; Valkyrie templates alongside) |
| Tabletop range plan | `tabletop-range-BOM-plan.md` |
| Launcher–catcher (bookend rig) design | `hardware/launcher-catcher.md`; bench-rig build notes in `finance/2026-08-28-bookend-rig-build-notes.md` |
| Expense ledger (reimbursement claim if the work project is approved) | `LEDGER.md`; double-entry in `finance/books/txns/2026.txn` (Tackler) |
| Receipts | `finance/receipts/YYYY-MM-DD-vendor-item.*` |

## Standing rules

- When Jim mentions a receipt or purchase: update `LEDGER.md`, post the
  Tackler entry, validate with
  `tackler --config finance/books/conf/tackler.toml --input.file finance/books/txns/2026.txn --reports balance`
  (if tackler is installed; otherwise just keep the journal consistent), and
  commit inside `finance/` (it is its own private git repo when `.git` is
  present; in the tarball it is plain files — that's fine).
- Everything on the bench stays ≤ 12 V, battery-direct, no capacitor bank.
- `make ci` is the gate for code changes (venv at `.venv`, Python 3.13).
- Management-facing files carry "MAIDEN" in the name, never generic
  "work briefing".
