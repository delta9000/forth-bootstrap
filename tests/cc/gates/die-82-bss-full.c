/* Error 82: global arrays fill the 256 MiB bss.  80,000,000 four-byte
   elements are 320 MB. */
int huge[80000000];
int main() {
  return 0;
}
