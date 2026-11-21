/* Error 91: a subscript on a name that is neither a local nor a global (a function). */
int f() { return 0; }
int main() { return f[0]; }
