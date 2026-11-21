/* The i386 back end has no 64-bit division: this must not compile. */
int
main (int argc, char **argv)
{
  long long a = 100;
  long long b = 7;
  show ("quotient", a / b);
  return 0;
}
