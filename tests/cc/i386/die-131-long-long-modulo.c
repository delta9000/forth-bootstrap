/* Nor a 64-bit remainder, in a compound assignment either. */
int
main (int argc, char **argv)
{
  unsigned long long a = 100;
  a %= 7;
  show ("remainder", a);
  return 0;
}
