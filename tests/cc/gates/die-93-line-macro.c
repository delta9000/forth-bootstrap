/* Error 93: there is no __LINE__ or __FILE__ macro, so the name is an
   unknown identifier. */
int
main (int argc, char **argv)
{
  return __LINE__;
}
