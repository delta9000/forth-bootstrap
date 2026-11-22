# Error 35: macro names and bodies overflow the 256 KiB macro pool.  Each
# #define here puts a 100-byte name and a 100-byte body in it.
awk 'BEGIN {
    for (i = 1; i <= 1400; i++) {
        printf "#define M%04d", i
        for (j = 0; j < 95; j++) printf "x"
        printf " "
        for (j = 0; j < 100; j++) printf "1"
        print ""
    }
}'
echo "int main() { return 0; }"
