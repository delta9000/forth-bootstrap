/* Error 58: a struct field 'struct' not followed by a tag name. */
struct s { struct 1 x; };
int main() { return 0; }
