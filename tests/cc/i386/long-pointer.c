/* 4-byte long and pointers: sizes, wraparound, pointer arithmetic. */
int numbers[10] = { 0, 10, 20, 30, 40, 50, 60, 70, 80, 90 };
struct item { char tag; int value; short more; };
struct item items[4];

int
main (int argc, char **argv)
{
  long l = 0x7fffffff;
  unsigned long ul = 0xffffffffUL;
  int *p = numbers + 5;
  int *q;
  char *text = "abcdefgh";
  struct item *it = items + 1;
  unsigned zero = 0;
  int minus = -2;
  int a = -17;
  int b = 5;
  unsigned ua = 0xfffffff0U;

  show ("size-long", sizeof (long));
  show ("size-ulong", sizeof (unsigned long));
  show ("size-pointer", sizeof (void *));
  show ("size-pp", sizeof (char **));
  show ("size-int", sizeof (int));
  show ("size-short", sizeof (short));
  show ("size-ll", sizeof (long long));
  show ("size-array", sizeof numbers);
  show ("size-item", sizeof (struct item));

  l = l + 1; show ("long-wrap", l);
  show ("long-wrap-ll", (long long) l);
  ul = ul + 1; show ("ulong-wrap", ul);
  ul = ul - 1; show ("ulong-back", ul);
  show ("ulong-ll", (long long) ul);
  show ("ulong-shift", ul >> 4);
  show ("long-shift", l >> 4);
  show ("long-mul", (long) 0x10000 * 0x10000);
  show ("ulong-mul", 0x12345UL * 0x10000UL);

  show ("deref", *p);
  show ("index", p[2]);
  show ("neg-index", p[-2]);
  show ("var-index", p[minus]);
  show ("unsigned-index", p[zero - 1]);
  show ("plus", *(p + 3));
  show ("minus", *(p - 4));
  show ("int-plus", *(2 + p));
  q = p; q++; show ("inc", *q);
  q--; q--; show ("dec", *q);
  q += 3; show ("pluseq", *q);
  q -= 5; show ("minuseq", *q);
  show ("post", *q++);
  show ("post2", *q);
  show ("diff", q - numbers);
  show ("diff-neg", numbers - q);
  show ("diff-char", (char *) q - (char *) numbers);
  show ("less", numbers < q);
  show ("greater", numbers > q);
  show ("equal", q == numbers + 3);
  show ("null", q == 0);
  show ("not", !q);
  show ("truth", q && 1);
  show ("char", text[3]);
  show ("char-ptr", *(text + 7));
  show ("pointer-long", (long) (q + 1) - (long) q);
  show ("pointer-ll", (long long) (unsigned long) (q + 1) - (long long) (unsigned long) q);

  it->tag = 'x'; it->value = -9; it->more = 77;
  items[2].value = 1234;
  show ("item-value", it->value);
  show ("item-next", (it + 1)->value);
  show ("item-more", it[0].more);
  show ("item-step", (char *) (it + 1) - (char *) it);
  show ("item-diff", &items[3] - it);
  show ("field-address", (char *) &it->more - (char *) it);

  show ("div", a / b);
  show ("mod", a % b);
  show ("div-neg", a / -b);
  show ("mod-neg", a % -b);
  show ("udiv", ua / 7);
  show ("umod", ua % 7);
  show ("udiv-big", ua / 0x80000000U);
  show ("mixed-div", ua / b);
  show ("shl", 1 << 31);
  show ("sar", a >> 2);
  show ("shr", ua >> 2);
  show ("int-less", a < b);
  show ("unsigned-less", ua < 5U);
  show ("mixed-less", a < ua);
  show ("char-less", (char) 200 < 0);
  show ("overflow", 0x7fffffff + b);
  show ("int-mul", 0x10000 * 0x10000 + a);
  show ("int-neg", -a);
  show ("int-not", ~a);
  a /= 3; show ("diveq", a);
  ua %= 9; show ("modeq", ua);
  return 0;
}
