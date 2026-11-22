/* Error 58: the compiler has no bitfields; the ':' is where it wants the
   member's ';'. */
struct s { int a : 3; int b : 5; };

int
main (int argc, char **argv)
{
  struct s x;
  x.a = 1;
  return x.a;
}
