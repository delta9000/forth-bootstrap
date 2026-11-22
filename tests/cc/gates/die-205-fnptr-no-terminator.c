/* Error 205: a function-pointer local followed by neither '=' nor ';'. */
int main() { int (*fp)(int) 5; return 0; }
