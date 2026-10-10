# Recorded results

Reports copied from runs on korriban: an x86-64 host with 24 hardware
threads and 30 GiB of RAM, QEMU with KVM.  Nothing here is an input to
any build; these files are what the runs wrote, kept so the figures in
the top-level README can be checked against them.

## `host-2026-10-08/`: `sh chain/plumbing-root.sh`

The sealed host run (hex0-seed to the GCC 4.0.4 fixed point), 2026-10-08,
18 minutes wall clock for all four entries.  `chain/plumbing/chain.kaem`
runs the GCC chain with `chain.sh -j 6`.

| File | What |
|---|---|
| `stage-d-report.txt` | stage D's verdict: stage 3 vs stage 4 and stage 2 vs stage 3, 54 files each, 0 differ; each stage's build time and the sha256 of every installed file |
| `execve-summary.txt` | 63,048 successful `execve` calls (4 of them the host's `bwrap` entering the root), 2,581 distinct paths, 249 failed lookups |
| `execve-programs.txt` | every path that executed, with its count (`chain/plumbing-root.sh` writes this) |
| `execve-failed.txt` | every failed `execve`, with its count: programs looked up and not found |

## `k1-2026-10-08/`: `JOBS=2 kernel/k1/run-chain.sh --direct-linux`

hex0 to Linux under K1, 2026-10-08, 1 h 38 min with `K1_MEM=24G`.  K1
uses one CPU, so `JOBS=2` only overlaps one job's I/O with another's
compiling.  The host run above builds the same chain to stage D in
18 minutes, with `-j 6` jobs on 24 threads.  From `serial.log`: the GCC
chain to stage D took 2,130 s, the late tools 631 s, and gcc64's bridge
and stages 6-10 2,334 s.

| File | What |
|---|---|
| `serial.log` | the guest's console, from K0 handing over to K1 to the Linux init's greeting (K0's hand-over line then read `k0: K1 built by seed Forth (no TinyCC); handing over`; it now ends at "Forth") |
| `binutils-report.txt`, `stage-c-report.txt`, `stage-d-report.txt` | the GCC chain's reports, written under K1 |
| `late-tools-report.txt` | the late tools: each package's configure and make times, and the sha256 of every installed program |
| `gcc64-hashes.txt` | the sha256 of each gcc64 output; all 31 entries of `chain/gcc64/HASHES` match |
| `gcc64-timings.txt` | gcc64's bridge and stages 6-10, in seconds |
| `bzImage.sha256` | the Linux 7.2.8 kernel the run built: sha256 and size (1,278,976 bytes) |

These were read from the run's output disk (`out.img`, a tar written by
`chain/ladder/finish.sh`) and its `serial.log`.

## `check-all-2026-10-10.txt`

`./check-all.sh` on 2026-10-10: 7 OK, 0 SKIP, 0 FAIL, with the last
lines of each step's log.
