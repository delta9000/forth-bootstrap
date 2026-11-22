/* Error 100: a double is carried as 8 bytes and there is no arithmetic
   on it. */
int
main (int argc, char **argv)
{
  double d;
  d = 1.5;
  d = d + d;
  return 0;
}
