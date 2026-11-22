/* Bitfields are the object target's (cc/129-cc-bitfield.fth): this must
   not compile. */
struct s { int a : 3; int b : 5; };

int
main (int argc, char **argv)
{
  struct s x;
  x.a = 1;
  return x.a;
}
