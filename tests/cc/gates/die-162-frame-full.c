/* Error 162: a function's locals share one frame of 131,072 eight-byte
   slots (cc-native-frame-limit, 1 MiB).  int[262144] fills it exactly;
   the compiler dies on the next local's declaration. */
int f(int a, int b) {
  int full[262144];
  int one_too_many;
  full[0] = a;
  one_too_many = b;
  return full[0] + one_too_many;
}
int main() {
  return f(1, 2);
}
