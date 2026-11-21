/* Host TSC rate: rdtsc over 1 s of CLOCK_MONOTONIC. */
#include <stdio.h>
#include <time.h>
#include <x86intrin.h>
int main(void) {
    struct timespec a, b; unsigned long long t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &a); t0 = __rdtsc();
    do clock_gettime(CLOCK_MONOTONIC, &b); while ((b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec) < 1e9);
    t1 = __rdtsc();
    printf("host TSC %.1f MHz\n", (t1 - t0) / (((b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec)) / 1e3));
    return 0;
}
