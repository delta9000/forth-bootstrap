/* Variadic functions: each argument is one slot, whatever its type. */
long long
sum (int count, ...)
{
  va_list ap;
  long long total = 0;
  va_start (ap, count);
  while (count)
    {
      total = total + va_arg (ap, int);
      count = count - 1;
    }
  va_end (ap);
  return total;
}

long long
mixed (char *kinds, ...)
{
  va_list ap;
  long long total = 0;
  va_start (ap, kinds);
  while (*kinds)
    {
      if (*kinds == 'i')
        total = total + va_arg (ap, int);
      if (*kinds == 'u')
        total = total + va_arg (ap, unsigned);
      if (*kinds == 'w')
        total = total ^ va_arg (ap, long long);
      if (*kinds == 's')
        total = total + va_arg (ap, char *)[0];
      if (*kinds == 'p')
        total = total + *va_arg (ap, int *);
      kinds = kinds + 1;
    }
  va_end (ap);
  return total;
}

int
main (int argc, char **argv)
{
  int local = 1000;
  show ("none", sum (0));
  show ("one", sum (1, -1));
  show ("five", sum (5, 1, 2, 3, 4, 0x7fffffff));
  show ("negative", sum (3, -100, -200, -300));
  show ("mixed", mixed ("iwsup", -1, 0x123456789abcdef0LL, "A", 0xffffffffU, &local));
  show ("wide-first", mixed ("wiw", -1LL, 5, 0x00ff00ff00ff00ffLL));
  return 0;
}
