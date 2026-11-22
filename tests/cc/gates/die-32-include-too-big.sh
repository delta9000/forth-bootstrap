# Error 32: an #include'd file does not fit the 1 MiB pool the files of
# the live #include stack share.
head -c 1048576 /dev/zero | tr '\0' '\n' > "$CC_DIE_TMP/big.h"
echo "#include \"$CC_DIE_TMP/big.h\""
echo "int main() { return 0; }"
