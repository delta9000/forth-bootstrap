/* long long arithmetic, logic, shifts and comparisons over operands whose
   halves carry and borrow into each other. */
unsigned long long tab[8] = { 0, 1, 0xffffffffULL, 0x100000000ULL, 0x123456789abcdef0ULL,
                              0x8000000000000000ULL, 0xffffffffffffffffULL, 0x7fffffff80000001ULL };

int
main (int argc, char **argv)
{
  int i;
  int j;
  int s;
  for (i = 0; i < 8; i = i + 1)
    for (j = 0; j < 8; j = j + 1)
      {
        unsigned long long a = tab[i];
        unsigned long long b = tab[j];
        long long sa = a;
        long long sb = b;
        show ("add", a + b);
        show ("sub", a - b);
        show ("mul", a * b);
        show ("and", a & b);
        show ("or", a | b);
        show ("xor", a ^ b);
        show ("sadd", sa + sb);
        show ("ssub", sa - sb);
        show ("smul", sa * sb);
        show ("eq", a == b);
        show ("ne", a != b);
        show ("ult", a < b);
        show ("ule", a <= b);
        show ("ugt", a > b);
        show ("uge", a >= b);
        show ("slt", sa < sb);
        show ("sle", sa <= sb);
        show ("sgt", sa > sb);
        show ("sge", sa >= sb);
        show ("mixed", sa < 1);
        show ("mixed2", a > 0xffffffffU);
      }
  for (i = 0; i < 8; i = i + 1)
    {
      unsigned long long a = tab[i];
      long long sa = a;
      show ("neg", -a);
      show ("not", ~a);
      show ("sneg", -sa);
      show ("lnot", !a);
      show ("truth", a ? 1 : 0);
      show ("and2", a && 1);
      show ("or2", a || 0);
      if (a)
        out ("nonzero\n");
      for (s = 0; s < 64; s = s + 1)
        {
          show ("shl", a << s);
          show ("shr", a >> s);
          show ("sar", sa >> s);
        }
      show ("shl32", a << 32);
      show ("shr32", a >> 32);
      show ("sar63", sa >> 63);
      a = a + 1;
      show ("inc", a);
      a++;
      show ("inc2", a);
      --a;
      show ("dec", a);
      show ("post", a--);
      show ("after", a);
      sa += 0x7fffffff;
      show ("pluseq", sa);
      sa -= 1;
      show ("minuseq", sa);
      sa <<= 3;
      show ("shleq", sa);
      sa >>= 5;
      show ("sareq", sa);
      sa |= 0x100000000LL;
      show ("oreq", sa);
      sa &= ~0xffLL;
      show ("andeq", sa);
      sa ^= 0x5555555555555555LL;
      show ("xoreq", sa);
      sa *= 3;
      show ("muleq", sa);
    }
  return 0;
}
