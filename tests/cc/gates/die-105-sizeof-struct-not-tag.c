/* Error 105: sizeof(struct NAME) where NAME is a variable, not a struct tag. */
int x;
int main() { return sizeof(struct x); }
