/* Error 101: '.' followed by something other than a member name. */
struct s { int a; };
int main() { struct s x; return x.1; }
