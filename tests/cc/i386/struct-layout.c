/* Struct and union layout under ILP32: offsets, sizes, copies. */
struct mixed { char c; short s; int i; long l; long long w; char *p; double d; char tail; };
struct wide_first { long long w; char c; };
struct chars { char a; char b; char c; };
struct nested { char c; struct mixed m; struct chars t; short s; };
struct arrays { char name[5]; int values[3]; long long wides[2]; char end; };
union shared { char c; long long w; int i; char bytes[11]; };
struct linked { struct linked *next; int value; };

struct mixed gm;
struct nested gn;
struct arrays ga;

int
main (int argc, char **argv)
{
  struct mixed m;
  struct mixed copy;
  struct nested n;
  union shared u;
  struct linked first;
  struct linked second;
  struct linked *walk;
  int i;

  show ("mixed", sizeof (struct mixed));
  show ("mixed.s", (char *) &gm.s - (char *) &gm);
  show ("mixed.i", (char *) &gm.i - (char *) &gm);
  show ("mixed.l", (char *) &gm.l - (char *) &gm);
  show ("mixed.w", (char *) &gm.w - (char *) &gm);
  show ("mixed.p", (char *) &gm.p - (char *) &gm);
  show ("mixed.d", (char *) &gm.d - (char *) &gm);
  show ("mixed.tail", (char *) &gm.tail - (char *) &gm);
  show ("wide_first", sizeof (struct wide_first));
  show ("chars", sizeof (struct chars));
  show ("nested", sizeof (struct nested));
  show ("nested.m", (char *) &gn.m - (char *) &gn);
  show ("nested.m.w", (char *) &gn.m.w - (char *) &gn);
  show ("nested.t", (char *) &gn.t - (char *) &gn);
  show ("nested.s", (char *) &gn.s - (char *) &gn);
  show ("arrays", sizeof (struct arrays));
  show ("arrays.values", (char *) ga.values - (char *) &ga);
  show ("arrays.wides", (char *) ga.wides - (char *) &ga);
  show ("arrays.wides1", (char *) &ga.wides[1] - (char *) &ga);
  show ("arrays.end", (char *) &ga.end - (char *) &ga);
  show ("union", sizeof (union shared));
  show ("linked", sizeof (struct linked));
  show ("double", sizeof (double));
  show ("array-of", sizeof (struct wide_first[3]));

  m.c = 'a'; m.s = -2; m.i = -3; m.l = -4; m.w = -0x500000000LL; m.p = "text"; m.tail = 'z';
  copy = m;
  show ("copy.c", copy.c);
  show ("copy.s", copy.s);
  show ("copy.i", copy.i);
  show ("copy.l", copy.l);
  show ("copy.w", copy.w);
  show ("copy.p", copy.p[1]);
  show ("copy.tail", copy.tail);
  n.m = m;
  n.c = 1; n.s = 2;
  show ("n.m.w", n.m.w);
  show ("n.m.tail", n.m.tail);
  gm = n.m;
  show ("gm.w", gm.w);
  show ("gm.s", gm.s);

  u.w = 0x1122334455667788LL;
  show ("u.c", u.c);
  show ("u.i", u.i);
  show ("u.byte7", u.bytes[7]);
  u.i = -1;
  show ("u.w", u.w);

  first.value = 10; first.next = &second;
  second.value = 20; second.next = 0;
  i = 0;
  for (walk = &first; walk; walk = walk->next)
    i = i + walk->value;
  show ("walk", i);
  for (i = 0; i < 3; i = i + 1)
    ga.values[i] = i * 100 - 1;
  ga.wides[1] = (long long) ga.values[2] << 32;
  ga.end = 9;
  show ("ga.values1", ga.values[1]);
  show ("ga.wides1", ga.wides[1]);
  show ("ga.end", ga.end);
  return 0;
}
