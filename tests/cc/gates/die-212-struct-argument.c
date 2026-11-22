/* Error 212: a struct cannot be passed by value. */
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
