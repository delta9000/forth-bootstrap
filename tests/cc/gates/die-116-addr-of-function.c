/* Error 116: unary & on a function name. */
int f() { return 0; }
int main() { int *p; p = &f; return 0; }
