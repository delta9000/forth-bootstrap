# Error 50: a struct with more than 1,023 members (cc-sd-field-cap).
echo "struct wide {"
awk 'BEGIN { for (i = 0; i < 1024; i++) print "  int f" i ";" }'
echo "};"
echo "int main() { return 0; }"
