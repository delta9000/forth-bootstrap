# chain/

The build chain from seed-cc to Linux, in the order it runs.
`runtime/gcc-seed/` is the C library seed-cc links programs against.
`plumbing/` builds the first tools with seed-cc and kaem scripts: make,
sed, grep, gawk, coreutils, tar, gzip, patch, diffutils, the parser
generators and bash 2.05b.  `gcc-direct/` uses them to build binutils 2.30
and GCC 4.0.4 (stage C), rebuild GCC to its fixed point (stage D), and
build the late tools.  `ladder/` and `gcc64/` climb from there to GCC
10.5.0 and build Linux 7.2.8.  `patches/` and `gcc-direct/patches/` hold
the few patches the chain applies; `plumbing-root.sh` runs everything up to stage D on the
host inside a root whose only executable is `hex0-seed`.  Start with
`plumbing/README.md`, then `plumbing/CHAIN.md` and `plumbing/LATE.md`.
Checks: `tools/check-pins.py` (`./check-all.sh` step 05);
`CHECK_CHAIN=1 ./check-all.sh` runs `plumbing-root.sh`; under K1 the
whole chain runs in `kernel/k1/run-chain.sh --direct-linux`.
