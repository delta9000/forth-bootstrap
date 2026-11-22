# Error 10: the 8 MiB arena is full.  A struct defined in a block takes a
# descriptor and a field table from the arena and its tag leaves the
# symbol table when the block ends, so the arena fills before the symbol
# table does (die-60).
echo "int main() {"
awk 'BEGIN { for (i = 0; i < 30000; i++) print "{ struct s { int a; }; }" }'
echo "return 0; }"
