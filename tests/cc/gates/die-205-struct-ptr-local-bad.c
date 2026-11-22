/* Error 205: a struct-pointer local followed by neither '=' nor ';'. */
struct s { int a; };
int main() { struct s *p 1; return 0; }
