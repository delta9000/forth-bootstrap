# Error 34: more than 4,096 macros (cc-macro-cap).
awk 'BEGIN { for (i = 1; i <= 4200; i++) print "#define M" i " " i }'
echo "int main() { return 0; }"
