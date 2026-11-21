/* Error 90: a member name the struct does not have. */
struct s { int a; };
int main() { struct s x; x.b = 1; return 0; }
