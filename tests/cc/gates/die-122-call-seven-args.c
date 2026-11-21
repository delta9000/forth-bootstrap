/* Error 122: a call with seven arguments; six is the limit. */
int f(int a, int b, int c, int d, int e, int f2, int g) { return a; }
int main() { return f(1,2,3,4,5,6,7); }
