/* __LINE__ and __FILE__ are the object target's (cc/124-cc-target.fth);
   native mode has no such macro, so the name is an unknown identifier:
   this must not compile. */
int
main (int argc, char **argv)
{
  return __LINE__;
}
