/* Error 131: there is no 64-bit remainder, in a compound assignment
   either. */
int
main (int argc, char **argv)
{
  unsigned long long a = 100;
  a %= 7;
  return a;
}
