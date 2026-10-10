# Representable integer absolute values

The checks this note names under `tests/gcc/` are seed-forth's
([tests/gcc/](https://github.com/delta9000/seed-forth/tree/0dd2b88/tests/gcc) at 0dd2b88); they were
not carried over.  Here the runtime is exercised by the chain itself:
every tool seed-cc builds links against it.

The original GCC 4.0.4 `libiberty/vasprintf.c` sizing pass uses `abs` for
star-supplied width and precision. `abs.c` implements the ordinary C `int`
operation, with its actual prototype in `stdlib.h`; the direct driver compiles
it from source with the other runtime members.

Zero, positive values, and negative values down to `-INT_MAX` have representable
results. As in ISO C, `abs(INT_MIN)` has undefined behavior because its
mathematical result is not representable as `int`. This implementation makes
no saturating or wraparound promise for that input.

`bash tests/gcc/abs-check.sh` checks zero, both signs, byte/short boundaries,
and both representable int endpoints through a function pointer. It runs a
Forth-only executable and independently host-built callers at `-O0` and `-O2`
against the Forth-built function object. The host objects never enter the
production executable.
