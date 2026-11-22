/* Error 31: #include nested deeper than 32 files (cc-prep-direct-depth).
   This file includes itself, so every level opens one more. */
#include "die-31-include-deep.c"
int main() { return 0; }
