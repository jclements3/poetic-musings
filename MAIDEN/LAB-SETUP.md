# LAB-SETUP.md — lab computer setup for MAIDEN / theremin hardware work

Takes a bare, internet-connected Linux machine to (a) flashing the prebuilt
bring-up bitstreams the day the boards arrive and (b) a full Clash
development loop. Do this BEFORE the boards arrive: step 4 runs unattended
for an hour or more, and it gates the pin-fix contingency in step 5.

Steps are ordered so the long unattended builds start first. The VHDL-side
setup (udev rules, usbipd on WSL, phase1 flow) is documented in the theremin
repo — `fpga/ROADMAP.md` Phase 0 and `CLAUDE.md` — and is referenced, not
repeated, here.

## 0. Ground rules

- The two machines sync **only through git** (`github.com/jclements3/maiden`
  and `github.com/jclements3/theremin`). Uncommitted work on one machine is
  invisible to the other: commit and push whenever you stop.
- The lab machine does all hardware/USB work. The home laptop (WSL2, no
  admin rights on the Windows host) cannot attach USB — never plan a flash
  step there.

## 1. Clone the repos (minutes)

> **Dropbox workflow (current plan, 28 Aug 2026):** if this tree was
> unpacked from `maiden.tar.bz2`, skip this section entirely — the repos
> and the private files are already here. See `CLAUDE.md` for the round
> trip back to Dropbox. Go to §2.

```sh
mkdir -p ~/projects && cd ~/projects
git clone https://github.com/jclements3/maiden.git
git clone https://github.com/jclements3/theremin.git
```

Optional, only for comparing against the original upstream design (213 MB):

```sh
git clone https://github.com/fpga-theremin/theremin.git \
    ~/projects/maiden/theremin/fpga-theremin
```

**GitHub push credentials — do not skip.** Cloning works anonymously, but
pushing does not, and pushing is how lab work gets home (rule 0). Either:

```sh
gh auth login        # if the gh CLI is installed; browser device-code flow
```

or generate an SSH key (`ssh-keygen -t ed25519`), add the public key at
github.com → Settings → SSH keys, and switch the remotes:

```sh
git remote set-url origin git@github.com:jclements3/maiden.git   # per repo
```

Verify with a trivial commit+push before the boards arrive.

## 2. FPGA toolchain — pinned OSS CAD Suite (minutes)

Pinned release **2026-08-20** (GHDL 7.0.0-dev, Yosys 0.68, nextpnr 0.11.1),
installed at `~/tools/oss-cad-suite` — the Makefiles assume that path. It
bundles everything the hardware flow needs, including `openFPGALoader` and
`iceprog`.

```sh
mkdir -p ~/tools && cd ~/tools
curl -LO https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-08-20/oss-cad-suite-linux-x64-20260820.tgz
tar xzf oss-cad-suite-linux-x64-20260820.tgz
```

Activate **per shell**, never in `.bashrc` (it shadows the system python3):

```sh
source ~/tools/oss-cad-suite/environment
```

**glibc shim (conditional):** if `ldd --version` reports glibc < 2.38
(e.g. Ubuntu 22.04), GHDL elaboration fails at link time on `__isoc23_*`
symbols. Build the shim per the theremin repo's `fpga/ROADMAP.md`
(`gcc -c -O2 -fPIC -o ~/tools/glibc-isoc23-shim.o glibc-isoc23-shim.c`);
the maiden Makefile picks it up automatically when
`~/tools/glibc-isoc23-shim.o` exists, and it is harmless to skip on a
newer distro.

## 3. USB permissions (minutes, needs sudo)

So flashing runs unprivileged (rules file travels in the theremin repo):

```sh
sudo cp ~/projects/theremin/fpga/setup/53-lattice-ftdi.rules /etc/udev/rules.d/
sudo udevadm control --reload
```

If the lab machine turns out to be Windows+WSL2 rather than native Linux,
additionally follow the usbipd-win steps in the theremin repo's
`fpga/ROADMAP.md` Phase 0 and run `fpga/setup/attach-fpga.sh` per plug-in.

**No sudo on the lab machine?** Everything else in this document works
unprivileged (ghcup, cabal, and the CAD suite all install under `~`).
Only this udev step needs root; the fallback is running the flash
commands under `sudo` (`sudo $(which openFPGALoader) ...` so the CAD
suite's PATH survives), or asking lab IT to install the rules file.

## 4. Haskell / Clash toolchain (start early — an hour+ unattended)

The Clash compiler is built from the project's own build plan
(`build-tool-depends`); a globally installed clash will not work. Pins:
GHC **9.6.7**, cabal-install **3.14.2.0**, clash-ghc **1.8.5** (from the
cabal.project freeze).

```sh
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
ghcup install ghc 9.6.7 && ghcup set ghc 9.6.7
ghcup install cabal 3.14.2.0 && ghcup set cabal 3.14.2.0

cd ~/projects/maiden/theremin/clash
cabal update
cabal build all        # long: builds clash-ghc and deps from source
cabal test             # behavioural suite; should be all green
```

The Makefile locates the project-built clash binary under
`~/.cabal/store/ghc-9.6.7/clash-ghc-1.8.5-e-clash-*/bin/clash` — nothing
else to configure once `cabal build all` succeeds.

## 5. Arrival day — flash and listen

Follow `theremin/clash/bringup/BRINGUP.md` end to end; it is the runbook.
The three bitstreams it flashes are prebuilt and tracked in git
(`bringup/bin/*.bin`), so this step works even if step 4 is still churning:

```sh
cd ~/projects/maiden/theremin/clash/bringup
source ~/tools/oss-cad-suite/environment
openFPGALoader --detect                      # FTDI device should appear
openFPGALoader -b alchitry_cu bin/blinky.bin # our flow, end to end
```

**Pin-fix contingency:** BRINGUP.md's procedure for wrong `theremin.pcf`
pin guesses re-runs nextpnr on `build/arrival/*.json`. Those netlists are
build outputs and are **not in git** — they regenerate from the Makefile
targets named in BRINGUP.md, which needs step 4 finished. That is the
reason step 4 starts before the boards arrive. (They also travel in the
`maiden.tar.bz2` asset on the repo's `arrival-v1` GitHub release.)

**ULX3S 85F** (the MAIDEN target board, ORDERS.md §1): its arrival-day
blinky is prebuilt and tracked at `bringup/bin/ulx3s-blinky.bit`
(pins from the official vendored `bringup/ulx3s/ulx3s_v20.lpf`, so no
pin-guess caveat here). Plain micro-USB, no programmer needed:

```sh
openFPGALoader -b ulx3s bin/ulx3s-blinky.bit     # SRAM load, volatile
```

One LED walks the 8-LED bank, full sweep ~1.3 s. Rebuild from source
with `make ulx3s-blinky` (needs only the CAD suite, not Haskell); later
theremin/MAIDEN ECP5 builds pack bitstreams with `make bit`.

## 6. Verify the development loop

Clash side (this repo):

```sh
cd ~/projects/maiden/theremin/clash
source ~/tools/oss-cad-suite/environment
make test    # Haskell behavioural tests
make sim     # Clash -> VHDL -> GHDL elaboration
make pnr     # ECP5 synthesis + P&R (the numbers that matter)
```

VHDL side (theremin repo): `cd ~/projects/theremin/fpga/phase1` and
`make sim && make bit && make prog` per that repo's CLAUDE.md — never
flash what hasn't been simulated.

## What to bring (physical checklist)

Collected from BRINGUP.md and ORDERS.md so nothing forces a second trip:

- **Micro-USB DATA cable** — the single most likely day-one blocker;
  most micro-USB cables are charge-only. Bring two.
- 0.1" header strip + access to a soldering iron, in case the Alchitry
  Cu ships unpopulated (BRINGUP.md step 0).
- Audio probe parts for BRINGUP.md step 3: 1 kOhm resistor, 10 nF cap,
  a powered speaker, and jumper wire for the step-4 jumper test.
- Oscilloscope or frequency counter access for the Colpitts oscillator
  stage (ORDERS.md §4 calls it the most likely bring-up blocker), plus
  breadboard + jumpers and the oscillator parts if they have arrived.
- The ULX3S's 3.5 mm audio jack needs only ordinary headphones or a
  powered speaker with a 3.5 mm plug.

## Done when

- [ ] A test commit pushed from the lab machine and pulled at home
      (proves the credentials step, before anything depends on it)
- [x] `cabal test` green in `maiden/theremin/clash` (11 Sep 2026, 98 cases incl. the new NoteMapSpec)
- [ ] `make sim` and `make pnr` complete in `maiden/theremin/clash`
- [x] `openFPGALoader --detect` sees a board (11 Sep 2026: opens the FT2232; iceprog is the Cu flasher, no alchitry_cu profile in openFPGALoader 1.1.1)
- [x] Alchitry Cu: `bin/blinky.bin` flashed and blinking (11 Sep 2026; then theremin-gui.bin, see BRINGUP.md section 6)
- [ ] ULX3S: `bin/ulx3s-blinky.bit` flashed and walking
