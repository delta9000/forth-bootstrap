# Error 80: initialized file-scope data fills the 64 KiB data area.  One
# array of 8,193 eight-byte elements with an initializer is 8 bytes too
# many.  (Data without an initializer goes to the bss instead: die-82.)
echo "long long a[8193] = {1};"
echo "int main() { return 0; }"
