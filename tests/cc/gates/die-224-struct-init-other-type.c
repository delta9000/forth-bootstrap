/* Error 224: a struct initialized from a value of another struct type. */
struct s { int a; };
struct t { int b; };
struct t y;
int main() { struct s x = y; return 0; }
