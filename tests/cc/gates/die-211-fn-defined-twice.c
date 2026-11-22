/* Error 211: a second body for a function already defined. */
int f() { return 0; }
int f() { return 1; }
int main() { return 0; }
