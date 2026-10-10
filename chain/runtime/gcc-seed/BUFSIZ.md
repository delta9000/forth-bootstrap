# Application stream block size

BUFSIZ is an integer constant 8192, exceeding the standard minimum 256. It is
the recommended application I/O block allocation size and the default
stream buffer size ([STDIO-BUFFERING.md](STDIO-BUFFERING.md)). Unchanged
Heirloom lex emits YYLMAX BUFSIZ into generated scanners; those scanners
allocate real token arrays of that bound.

Arrays sized by the macro were compiled through Forth, the complete8192-byte
buffer was written and read with the real runtime, every byte was checked
independently, and EOF/error indicators were verified. The source has a compile-time
minimum-size check. Larger scanner token limits still require the original
scanner's explicit YYLMAX override; no scanner source adaptation is needed.
