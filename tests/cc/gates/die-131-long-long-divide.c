/* Error 131: there is no 64-bit division. */
int
main (int argc, char **argv)
{
  long long a = 100;
  long long b = 7;
  return a / b;
}
