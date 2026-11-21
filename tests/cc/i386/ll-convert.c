/* Conversions to and from long long, truncation, high halves, long long
   in memory and across calls. */
struct pair { int before; long long wide; char after; };
long long global = 0x1122334455667788LL;
long long array[3];

long long
widen (int v)
{
  return v;
}

long long
uwiden (unsigned v)
{
  return v;
}

int
narrow (long long v)
{
  return v;
}

long long
pass (long long a, int b, long long c, char d)
{
  return a + b + c + d;
}

/* The lexer of tcc builds a number this way. */
unsigned long long
accumulate (char *digits, int base)
{
  unsigned long long n = 0;
  while (*digits)
    {
      n = n * base + (*digits - '0');
      digits = digits + 1;
    }
  return n;
}

int
main (int argc, char **argv)
{
  int i = -5;
  unsigned u = 0xfffffffbU;
  char c = -3;
  unsigned char uc = 200;
  short s = -30000;
  unsigned short us = 60000;
  long l = -7;
  unsigned long ul = 0x80000001UL;
  long long ll;
  unsigned long long ull;
  long long *p = &global;
  struct pair pr;
  int bits;

  ll = i; show ("int", ll);
  ll = u; show ("unsigned", ll);
  ll = c; show ("char", ll);
  ll = uc; show ("uchar", ll);
  ll = s; show ("short", ll);
  ll = us; show ("ushort", ll);
  ll = l; show ("long", ll);
  ll = ul; show ("ulong", ll);
  ull = i; show ("int-u", ull);
  ull = c; show ("char-u", ull);
  show ("widen", widen (-2));
  show ("uwiden", uwiden (0xfffffffeU));
  show ("cast", (long long) i * 0x10000);
  show ("ucast", (unsigned long long) u * 0x10000);
  show ("nocast", i * 0x10000);

  ll = 0x89abcdef01234567LL;
  i = ll; show ("to-int", i);
  u = ll; show ("to-unsigned", u);
  c = ll; show ("to-char", c);
  uc = ll; show ("to-uchar", uc);
  s = ll; show ("to-short", s);
  us = ll; show ("to-ushort", us);
  l = ll; show ("to-long", l);
  ul = ll; show ("to-ulong", ul);
  show ("narrow", narrow (ll));
  show ("high", (int) (ll >> 32));
  show ("uhigh", (unsigned) ((unsigned long long) ll >> 32));
  show ("low", (int) ll);
  show ("high-first", ll >> 31 ? 1 : 0);

  show ("global", global);
  show ("deref", *p);
  *p |= 0xff00000000000000LL;
  show ("or-through", global);
  *p = *p + 0x100000000LL;
  show ("add-through", global);
  array[1] = -1;
  array[2] = array[1] << 33;
  show ("array0", array[0]);
  show ("array2", array[2]);
  pr.before = 1;
  pr.wide = 0x0102030405060708LL;
  pr.after = 2;
  show ("member", pr.wide);
  show ("member-or", pr.wide | pr.before);
  pr.wide >>= 8;
  show ("member-shift", pr.wide);
  show ("pass", pass (0x100000000LL, -1, 0x7fffffffffffffffLL, 1));

  for (bits = 1; bits < 64; bits = bits + 7)
    {
      long long mask = (1LL << bits) - 1;
      show ("mask", mask);
      show ("masked", 0xfedcba9876543210ULL & mask);
    }
  show ("minus-one", -1LL);
  show ("accumulate", accumulate ("18446744073709551615", 10));
  show ("accumulate8", accumulate ("1777777777777777777777", 8));
  show ("accumulate-small", accumulate ("4294967296", 10));

  show ("size-int", sizeof (2147483647));
  show ("size-big", sizeof (2147483648));
  show ("size-hex", sizeof (0x80000000));
  show ("size-hex-big", sizeof (0x100000000));
  show ("size-l", sizeof (1L));
  show ("size-ul", sizeof (1UL));
  show ("size-ll", sizeof (1LL));
  show ("size-u", sizeof (4294967295U));
  show ("big", 2147483648);
  show ("hex", 0x80000000);
  show ("neg-hex", -0x80000000);
  show ("wide", 0xffffffffffffffff);
  show ("sum", 0x7fffffff + 1LL);
  return 0;
}
