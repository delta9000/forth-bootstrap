/* tinycc/libc-sscanf.c -- sscanf for pnut's portable libc, as much of it as
   tcc needs.  Ours (MIT, as the repository); not from pnut.

   pnut's portable_libc (udem-dlteam/pnut abc34a5207b1373d0a4e3dcb3d3d6df6e22ae23d)
   declares sscanf in include/stdio.h but leaves its definition commented out
   in src/stdio.c, with a note that "TCC only uses "%d.%d.%d"".  janneke's
   tcc-0.9.26-1147-gee75a10c calls it once, in libtcc.c, to read TCC_VERSION
   into __TINYC__:
       sscanf(TCC_VERSION, "%d.%d.%d", &a, &b, &c);
   tinycc/direct-input.c includes this file after libc64/libc.c, so the
   first tcc is compiled from tcc's source as live-bootstrap has it, with no
   patch of ours.

   Supported: %d (optional sign, decimal digits, after any whitespace),
   whitespace in the format (skips any whitespace in the input) and other
   characters (must match).  Returns the number of %d stored, or -1 when the
   input ends before the first one.  Any other conversion aborts.
   "Whitespace" is space and \t to \r.  pnut's ctype.c defines isspace and
   isdigit only under ADD_LIBC_STUB, which the first tcc's build does not
   set, so the two tests are local. */
static int sscanf_space(int c)
{
    return c == ' ' || (c >= '\t' && c <= '\r');
}

static int sscanf_digit(int c)
{
    return c >= '0' && c <= '9';
}

int sscanf(const char *str, const char *format, ...)
{
    va_list ap;
    int n = 0;
    int neg;
    int val;
    char c;

    va_start(ap, format);
    while ((c = *format++)) {
        if (c == '%' && *format != '%') {
            c = *format++;
            if (c != 'd')
                pnut_abort("sscanf: only %d is supported");
            while (sscanf_space(*str))
                str++;
            if (*str == 0)
                return n ? n : -1;
            neg = 0;
            if (*str == '+' || *str == '-') {
                neg = *str == '-';
                str++;
            }
            if (!sscanf_digit(*str))
                return n;
            val = 0;
            while (sscanf_digit(*str))
                val = val * 10 + (*str++ - '0');
            *va_arg(ap, int *) = neg ? -val : val;
            n++;
        } else if (sscanf_space(c)) {
            while (sscanf_space(*str))
                str++;
        } else {
            if (c == '%')
                format++;
            if (*str != c)
                return n;
            str++;
        }
    }
    va_end(ap);
    return n;
}
