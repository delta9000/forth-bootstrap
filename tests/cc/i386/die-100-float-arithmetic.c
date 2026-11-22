/* Native mode carries a double as 8 bytes and has no arithmetic on it
   (cc/127-cc-binary64.fth is the object target's): this must not compile. */
int
main (int argc, char **argv)
{
  double d;
  d = 1.5;
  d = d + d;
  return 0;
}
