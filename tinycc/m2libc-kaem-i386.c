/* tinycc/m2libc-kaem-i386.c -- the process calls of M2libc's x86/linux
   layer, for kaem alone.

   vendor/mescc-tools/Kaem starts each command with fork, execve and
   waitpid.  M2libc has them in M1 assembly
   (vendor/stage0-posix/M2libc/x86/linux/unistd.c); these are the same
   calls on __native_syscall.  The file goes between
   tinycc/m2libc-native-i386.c and kaem's sources, and before no other
   program's: the eleven tools make none of these calls, and their bytes
   stay as they are without them.

   builder-hex0, the kernel kaem is for, differs from Linux in all three
   (tests/builder-hex0/README.md, sections 3 and 4):
     fork     answers 0 in the child and 1 in the parent.  kaem tests for
              -1 and 0 only.
     execve   of a file that is not there stops the machine, so access is
              asked first and a missing file is answered with -1, as
              Linux would.  kaem's child then exits; on builder-hex0 the
              parent is not resumed after that, and its shell runs the
              next command.
     waitpid  answers 0 and stores the exit code shifted left by 8, not
              masked to 8 bits.  kaem reads bits 8 to 15. */

int
fork ()
{
  return __native_syscall (2, 0, 0, 0, 0, 0, 0);
}

int
waitpid (int pid, int *status_ptr, int options)
{
  return __native_syscall (7, pid, (long) status_ptr, options, 0, 0, 0);
}

int
execve (char *file_name, char **argv, char **envp)
{
  if (0 != access (file_name, 0))
    return -1;
  return __native_syscall (11, (long) file_name, (long) argv, (long) envp, 0, 0, 0);
}
