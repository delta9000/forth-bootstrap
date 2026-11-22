/* Error 219: a file-scope initializer that is not a constant. */
int f() { return 1; }
int x = f();
int main() { return 0; }
