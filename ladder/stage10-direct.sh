# ladder/stage10-direct.sh: the late tools become the system.  Run under K1
# by k1/direct-linux.recipe with the late bash as
#   /build-out/late/usr/bin/bash /ladder/stage10-direct.sh
# after k1/direct-full.sh, whose gcc-direct/late-tools.sh built make 4.4.1,
# bash 5.2, coreutils 9.5 and the rest with the stage-D GCC.  This installs
# them as /usr (/usr/bin, /bin/sh = bash 5.2) and adds the helpers gcc64's
# scripts ask the system for, for ladder/stage11.sh.  (The name is
# seed-forth's: its TinyCC route had a stage 10 that built these with tcc.)
set -eu
L=/build-out/late/usr
B=/build-out/plumbing/bin
# /bin and /usr/bin are links to the plumbing tools (k1/direct-full.sh);
# from here on they are directories holding the late tools.
[ -L /usr/bin ] && $B/rm /usr/bin
[ -L /bin ] && $B/rm /bin
$B/mkdir -p /usr/bin /bin
$B/cp -R $L/. /usr/
$B/ln -s /usr/bin/bash /bin/sh
$B/ln -s /usr/bin/bash /bin/bash
export PATH=/usr/bin:/bin HOME=/ SHELL=/bin/sh LC_ALL=C TZ=UTC0
# Two answers gcc64's scripts ask the system for.
printf '#!/bin/sh\necho chain-root\n' > /usr/bin/hostname
cp /ladder/getconf.sh /usr/bin/getconf
cp /ladder/which.sh /usr/bin/which
[ -e /usr/bin/awk ] || ln -s gawk /usr/bin/awk
[ -e /usr/bin/install ] || ln -s ginstall /usr/bin/install
chmod 755 /usr/bin/hostname /usr/bin/getconf /usr/bin/which
for t in make bash sed grep gawk tar xz bzip2 m4 bison flex bc find diff patch; do
  /usr/bin/$t --version 2>&1 | head -n 1
done
echo "stage10: environment ready (direct route: tools built by the stage-D GCC)"
