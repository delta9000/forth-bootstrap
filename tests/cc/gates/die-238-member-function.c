/* Error 238: a struct member declared as a function. */
struct s { int f(); };
int main() { return 0; }
