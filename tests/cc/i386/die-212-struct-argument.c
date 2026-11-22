/* A struct passed by value is the object target's
   (cc/131-cc-aggregate-abi.fth): this must not compile. */
struct s { int a; int b; };

int
f (struct s x)
{
  return x.a;
}

int
main (int argc, char **argv)
{
  struct s x;
  x.a = 1;
  return f (x);
}
