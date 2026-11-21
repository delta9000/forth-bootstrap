/* Calls, switches and the narrow integer types: what the pair emitters
   must keep extended. */
int counter;
char bytes[4] = { 1, -1, 127, -128 };
short shorts[3] = { -1, 32767, -32768 };
char *names[3] = { "zero", "one", "two" };

int
many (int a, long long b, char c, int *d, short e, unsigned f, long long g)
{
  return a + (int) (b >> 32) + c + *d + e + (int) f + (int) g;
}

int
factorial (int n)
{
  if (n < 2)
    return 1;
  return n * factorial (n - 1);
}

int twice (int v) { return v + v; }
int square (int v) { return v * v; }

int
apply (int (*f) (int), int v)
{
  return f (v);
}

/* A 4-byte function pointer in memory, with other objects after it. */
int (*chosen) (int) = square;
int after_chosen = -1;
struct handler { int (*run) (int); int tag; };
struct handler handlers[2] = { { twice, 7 }, { square, 8 } };

char
as_char (int v)
{
  return v;
}

unsigned short
as_ushort (int v)
{
  return v;
}

int
classify (int v)
{
  switch (v)
    {
    case -1: return 10;
    case 0: return 20;
    case 1:
    case 2: return 30;
    case 0x7fffffff: return 40;
    case -0x7fffffff - 1: return 50;
    default: return 60;
    }
}

int
classify_wide (long long v)
{
  switch (v)
    {
    case 1: return 1;
    case 0x100000001LL: return 2;
    case -1: return 3;
    case 0xffffffffLL: return 4;
    default: return 5;
    }
}

int
classify_char (char c)
{
  int n = 0;
  switch (c)
    {
    case 'a': n = n + 1;
    case 'b': n = n + 10; break;
    case -56: n = 100; break;
    default: n = -1;
    }
  return n;
}

int
main (int argc, char **argv)
{
  int d = 7;
  int i;
  int total = 0;
  char c = 127;
  unsigned char uc = 255;
  short s = 32767;
  int (*f) (int) = twice;

  show ("argc", argc);
  show ("argv1", argv[1][0]);
  show ("many", many (1, 0x200000000LL, -3, &d, -5, 6, 0x7ffffffffLL));
  show ("factorial", factorial (10));
  show ("apply", apply (square, -12));
  show ("pointer", f (21));
  f = square;
  show ("pointer2", (*f) (5));
  show ("global-pointer", chosen (9));
  chosen = twice;
  show ("global-pointer2", chosen (9) + after_chosen);
  show ("member-pointer", handlers[1].run (handlers[0].tag));
  show ("member-pointer2", handlers[0].run (handlers[1].tag));
  show ("as-char", as_char (0x1234567f + 1));
  show ("as-ushort", as_ushort (-2));
  for (i = -2; i < 4; i = i + 1)
    show ("classify", classify (i));
  show ("classify-max", classify (0x7fffffff));
  show ("classify-min", classify (-0x7fffffff - 1));
  show ("wide1", classify_wide (1));
  show ("wide2", classify_wide (0x100000001LL));
  show ("wide3", classify_wide (-1));
  show ("wide4", classify_wide (0xffffffffLL));
  show ("wide5", classify_wide (0x200000001LL));
  show ("char-a", classify_char ('a'));
  show ("char-b", classify_char ('b'));
  show ("char-200", classify_char (200));
  show ("char-z", classify_char ('z'));

  c = c + 1; show ("char-wrap", c);
  uc = uc + 1; show ("uchar-wrap", uc);
  s = s + 1; show ("short-wrap", s);
  c += 100; show ("char-pluseq", c);
  c <<= 1; show ("char-shleq", c);
  uc -= 1; show ("uchar-minuseq", uc);
  uc++; show ("uchar-inc", uc);
  c--; show ("char-dec", c);
  s *= 2; show ("short-muleq", s);
  for (i = 0; i < 4; i = i + 1)
    total = total + bytes[i];
  show ("bytes", total);
  show ("byte3", bytes[3]);
  show ("short2", shorts[2]);
  show ("shorts", shorts[0] + shorts[1]);
  show ("name", names[2][1]);

  i = 0;
  do
    {
      counter = counter + i;
      i = i + 1;
    }
  while (i < 10);
  show ("do", counter);
  while (i)
    {
      if (i == 5)
        break;
      i = i - 1;
    }
  show ("break", i);
  for (i = 0; i < 20; i = i + 1)
    {
      if (i % 3)
        continue;
      counter = counter - 1;
    }
  show ("continue", counter);
  i = 3;
again:
  i = i - 1;
  if (i)
    goto again;
  show ("goto", i);
  show ("ternary", d > 5 ? -1 : 1);
  show ("and", d && counter);
  show ("or", 0 || d);
  show ("not", !d);
  show ("comma", (d = 3, d + 1));
  show ("nested", twice (square (twice (-3))));
  return 300;
}
