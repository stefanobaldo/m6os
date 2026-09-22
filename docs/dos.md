# MSX-DOS programs

m6 runs MSX-DOS 2 programs — `.COM` files — one at a time, each with the
machine to itself: the MSX-DOS 2 layout around it, the BIOS live, the
MSX-DOS 2 function calls served by m6 over its own files. When the
program ends, m6 is back where it was, with every process it had
suspended still there. This document says how to run one, what the
program finds, what it sees of the files, and what of MSX-DOS 2 is
there and what is not.

## Running a program

```
dos path [args...]
```

`dos` runs the program in the file `path`. A path with no dot in its last
component that is not found is tried again with `.com` appended, so
`dos ted t.txt` and `dos ted.com t.txt` are the same. The arguments,
joined by single spaces behind a leading one, are the program's command
tail, as MSX-DOS gives it — at most 127 bytes.

The shell does the same on its own for a command word ending in `.com`:
`ted.com t.txt` at the prompt runs `dos ted.com t.txt`, so a program's
name is enough. A word without `.com` is a native command, looked up in
`/bin` as always; a `.COM` file is never run by accident.

The program's status is its MSX-DOS termination code, and the shell
reports it the way it reports any command's: nothing for 0, `[7]` for a
program that ended with `_TERM` and code 7, `[158]` (`9Eh`, `.CTRLC`)
for one that Ctrl-C ended, `[159]` (`9Fh`, `.STOP`) for Ctrl-STOP.

While the program runs, nothing else does: m6's clock stands still, a
process asleep wakes late by the program's run, and a background job
waits. On a 128K machine the program needs every free segment — the
three pages of its TPA and one more for what is above it — so `dos` is
refused with `ENOMEM` while another process besides the shell is alive.

What serves the program's file calls is not above its TPA. It takes the
place of fifteen of the disk cache's twenty-two sector buffers for the
program's run, and is brought into page 2 for the length of a file call
and out again before the program goes on; the cache works with the seven
that are left, and the first command after the program finds the others
empty. During a file call interrupts are held off between the kernel's
own calls, for a few milliseconds at most: the BIOS's tick may come that
late, and none is lost.

The program's console is the screen and the keyboard, through the BIOS,
whatever the command line says: `dos prog.com > out` redirects nothing
the program prints, and `cat in | dos prog.com` feeds it nothing. The
standard handles of a `.COM` are the console, as at a prompt.

## What the program finds

The program is loaded at `0100h` and finds MSX-DOS 2 around it, as the
Program Interface Specification describes it:

- A TPA of 55.8K, from `0100h` to `DC06h`, the `JP` at `0005h` that is the
  BDOS entry and the top of the TPA — where Nextor puts it at its prompt.
  The six bytes under it are CP/M's version and serial, which a program
  that sets its stack at the address in `0006h` writes over, as under
  MSX-DOS.
- The registers of a function call as MSX-DOS 2 returns them: the error
  in `A` with the flags set from it, so that a branch on `Z` straight
  after `CALL 5` works; `IX` and `IY` as they went in.
- Its slots its own. A program may call the system with another slot in
  page 1 or page 2 — its strings in page 0 or 3 — and finds the same slots
  there when the call returns. An argument that lies in page 2 of the
  program's memory is reached wherever it is.
- Page 0 as the specification lays it out: the warm-boot jump at `0000h`
  into a CP/M BIOS jump table — every way a program ends, `ret`, `jp 0`
  and `_TERM`, goes through it, so a program that aims the table's
  warm-boot jump at its own code gets control back, as a file manager
  does to run a program and return — `RDSLT`, `WRSLT`, `CALSLT`, `ENASLT` and
  `CALLF` at `000Ch`–`0030h`, the interrupt vector at `0038h`, the two
  unopened FCBs at `005Ch` and `006Ch` built from the first two words of
  the tail, the tail itself at `0080h`, upper-cased, with its length
  before it, and `FFh` at `0037h`, the mark a program reads to know that
  `PARAMETERS` and `PROGRAM` are there to be asked for.
- The BIOS, live: every ROM routine reachable through `CALSLT`, the
  interrupt handler scanning the keyboard and counting `JIFFY`, `H.TIMI`
  and the other hooks the program may set. The console functions go
  through `CHPUT`, `CHGET` and `CHSNS`, so what the BIOS does with escape
  sequences and the cursor, the program gets.
- The mapper support routines, found through `EXTBIO` (`D` = 4, `E` = 1
  for the variable table, `E` = 2 for the jump table) as under MSX-DOS 2:
  `ALL_SEG`, `FRE_SEG`, `RD_SEG`, `WR_SEG`, `CAL_SEG`, `CALLS`, `PUT_Pn`
  and `GET_Pn` for pages 0–2. `ALL_SEG` answers the mapper's slot in `B`
  when it is asked by slot, and the routines keep `IX` and `IY`. A
  segment the program allocates is freed when it ends. On a 128K machine
  with a shell up there is none to give.
- `_DOSVER` answers kernel 2.31 and MSXDOS2.SYS 2.31. m6 is not Nextor
  and does not answer Nextor's handshake, so a program takes its MSX-DOS 2
  paths; the Nextor functions (`71h`–`7Eh`) are refused.
- `EXTBIO` answers the mapper support and nothing else: a program probing
  for another extension gets its registers back untouched, which is the
  "absent" answer.

## Drives, directories and names

The mounted volumes are the drives, `A:` to `H:` for `/mnt/a` to `/mnt/h`;
the login vector (`_LOGIN`) has a bit for each one that is mounted, and
`_SELDSK` refuses a letter that is not. When the program starts, the
current drive is the volume of the shell's current directory — the boot
volume when the shell is in `/mnt` — and that drive's current directory
is the shell's; every other drive is at its root. What the program
changes with `_SELDSK` and `_CHDIR` is its own: the shell's current
directory is what it was when the program ends.

Paths are MSX-DOS paths: a drive letter, `\` between components, `.` and
`..`, and names of up to eight characters, a dot and three, upper-cased
as they are looked up. The program sees every file by its short name:
a file that also has a long name on the disk is reached by its alias, and
the search functions and the directory functions report the alias, never
the long name. `_PARSE`, `_PFILE` and `_CHKCHR` upper-case ASCII letters
only. Volume labels are not shown: a search asking for them finds nothing.

`_ASSIGN` maps one drive letter to another for the program alone.

## The functions

The table says what each MSX-DOS 2 function does under m6. Functions not
in it, and the Nextor ones, return `.IBDOS` (invalid function call,
`DCh`); the CP/M-compatible ones answer `0`, `FFh` or `1` in `A` as
MSX-DOS 2 does, with the MSX-DOS 2 code for `_ERROR` and `_EXPLAIN`; `_IOCTL` with a subfunction it does not have returns `.ISBFN`
(`B8h`).

| Function | Under m6 |
|---|---|
| `00h` `_TERM0`, `62h` `_TERM` | ends the program through the abort routine and `jp 0`; the code in `B` is the status the shell reports |
| `01h` `_CONIN`, `07h` `_DIRIN`, `08h` `_INNOE` | a key from the BIOS, echoed by `_CONIN` only |
| `02h` `_CONOUT`, `09h` `_STROUT` | to the screen through the BIOS |
| `06h` `_DIRIO` | direct console I/O, as specified |
| `0Ah` `_BUFIN` | a line: BS and DEL take a byte back, RET ends it; no history |
| `0Bh` `_CONST` | whether a key waits |
| `0Ch` `_CPMVER` | `0022h` |
| `0Dh` `_DSKRST` | the transfer address back to `0080h`; every write already reached the disk |
| `0Eh` `_SELDSK` | the current drive; `.IDRV` for a drive that is not mounted; `A` = the number of drives |
| `18h` `_LOGIN` | a bit per mounted volume |
| `19h` `_CURDRV` | the current drive |
| `1Ah` `_SETDTA`, `57h` `_GETDTA` | the transfer address, kept and given back; nothing here uses it |
| `1Bh` `_ALLOC` | the sectors per cluster, the sector size, the clusters and the free ones; `IX` and `IY` come back 0 — there is no DPB and no FAT sector to point at. The free count walks the whole table, which takes about a second and a half on a 128 MB volume of an SD card |
| `2Ah` `_GDATE`, `2Ch` `_GTIME` | the clock's date, with the day of the week, and its time |
| `2Bh` `_SDATE`, `2Dh` `_STIME` | refused with `A` = `FFh`: a program does not set the clock |
| `2Eh` `_VERIFY`, `58h` `_GETVFY` | the flag, kept and given back; m6 verifies nothing |
| `31h` `_DPARM` | the volume's parameters as m6 has them: 512-byte sectors, the cluster size, the reserved sectors, the FATs, the root entries, the first root and data sectors and the highest cluster; the total sectors and the sectors per FAT 0 when the field cannot hold them, as MSX-DOS 2 answers for a volume too large to describe; media descriptor `F8h`; volume id `−1`; dirty flag 0 |
| `40h` `_FFIRST`, `41h` `_FNEXT` | a search by name pattern and attributes, the found entry in the FIB with its 8.3 alias; hidden and system entries, and directories, only when asked, `.` and `..` with the directories; `.NOFIL` at the end, and at once for the volume-label bit |
| `42h` `_FNEW` | a file made from the template, the `?`s filled from the FIB's name; still ambiguous is `.IFNM` |
| `43h` `_OPEN` | a file, or a directory as a FIB, or a device: `CON` for the console, `NUL`, `AUX` and `PRN` for a sink that reads nothing |
| `44h` `_CREATE` | a file, emptied when it exists unless bit 7 of `B` says so (`.FILEX`); with the directory bit a directory; the read-only, hidden and system bits set after |
| `45h` `_CLOSE`, `46h` `_ENSURE`, `47h` `_DUP`, `5Fh` `_FLUSH` | as specified; `_ENSURE` and `_FLUSH` have nothing to do, every write reaches the disk as it is made |
| `48h` `_READ`, `49h` `_WRITE` | the bytes moved in one piece; `.EOF` when a read finds none; a read asked for more than the memory from its buffer to the TPA's top is cut there, so a program that asks for "everything" of a short file gets it; `.IPARM` for a buffer that starts above the TPA; a write to a device in ASCII mode ends at the first `1Ah`, which is counted and not sent |
| `4Ah` `_SEEK` | by the three methods; a position that would go negative is `.IPARM` |
| `4Bh` `_IOCTL` | 0 the device or file status, with bit 6 for a file at its end; 1 ASCII or binary mode on a device; 2 and 3 whether input or output is ready; 4 the screen's size on the console |
| `4Ch` `_HTEST` | whether the handle is the named file |
| `4Dh` `_DELETE`, `52h` `_HDELETE` | a file, or an empty directory (`.DIRNE` otherwise); `.DOT` for `.` and `..` |
| `4Eh` `_RENAME`, `53h` `_HRENAME` | a new name in the same directory, `?`s filled from the old; `.DUPF` when it exists |
| `4Fh` `_MOVE`, `54h` `_HMOVE` | to another directory of the same drive; `.IDRV` across drives, `.DIRE` for a directory into itself |
| `50h` `_ATTR`, `55h` `_HATTR` | the attributes, read or set: read-only, hidden, system and archive, on a file or a directory; another bit is `.IATTR` |
| `51h` `_FTIME`, `56h` `_HFTIME` | the modification time, read or set |
| `59h` `_GETCD` | the drive's current directory, from its root, `\` between components |
| `5Ah` `_CHDIR` | the drive's current directory; `.NODIR` for what is not a directory |
| `5Bh` `_PARSE`, `5Ch` `_PFILE`, `5Dh` `_CHKCHR` | the string functions, as specified, with no disk access |
| `5Eh` `_WPATH` | the whole path of the last file found or made |
| `60h` `_FORK`, `61h` `_JOIN` | a level count: `_JOIN` closes the handles opened above the level it is given; segments the program allocated stay its own until it ends |
| `63h` `_DEFAB` | the abort routine, called when the program ends |
| `64h` `_DEFER` | the disk error routine, called for a disk error with the choice of abort, retry and ignore |
| `65h` `_ERROR` | the last error code |
| `66h` `_EXPLAIN` | the message for a code, in the MSX-DOS 2 words; `Error nnH` for one m6 does not know |
| `6Ah` `_ASSIGN` | a logical drive mapped to a physical one, queried, or cleared |
| `6Bh` `_GENV`, `6Ch` `_SENV`, `6Dh` `_FENV` | the environment: `PARAMETERS` is the command tail and `PROGRAM` the program's own path, drive and all; the rest is a store of 256 bytes, empty when the program starts — no `PATH`, no `PROMPT`, none of COMMAND2's strings |
| `6Eh` `_DSKCHK` | the flag, kept and given back |
| `6Fh` `_DOSVER` | 2.31, not Nextor |
| `70h` `_REDIR` | nothing is ever redirected: the state answers so, and setting it changes nothing |
| `03h` `_AUXIN`, `04h` `_AUXOUT`, `05h` `_LSTOUT` | the auxiliary input answers `1Ah`, the end; the auxiliary and list outputs swallow the byte |
| `0Fh` `_FOPEN` | the file an FCB names opened, for reading and writing — for reading alone when the file is read-only or someone writes it already; an ambiguous name opens the first file that matches, holding the extent asked; a device name (`CON`, `NUL`, `AUX`, `PRN`, `LST`) a device |
| `10h` `_FCLOSE` | the FCB's file closed; nothing waits to be written |
| `11h` `_SFIRST`, `12h` `_SNEXT` | the files matching the FCB's name in its drive's current directory, hidden ones too, no system files and no directories; the drive and the directory entry into the transfer address, the extent at `0Ch`, the attributes at `0Dh`, the record count at `0Fh` |
| `13h` `_FDEL` | every file matching the name deleted, but system, hidden and read-only ones |
| `14h` `_RDSEQ`, `15h` `_WRSEQ` | the record at the extent and the current record, which move on; a partial record read is padded with zeros |
| `16h` `_FMAKE` | with extent 0 the file made anew, an existing one emptied; with another extent the existing file opened |
| `17h` `_FREN` | every file matching the first name renamed to the second, a `?` there keeping the character it had; system and hidden files left alone |
| `21h` `_RDRND`, `22h` `_WRRND`, `28h` `_WRZER` | the record the random record names; what a write leaves between the end and it is zeros, for both writes |
| `23h` `_FSIZE` | the file's size in records into the random record |
| `24h` `_SETRND` | the random record from the extent and the current record |
| `26h` `_WRBLK`, `27h` `_RDBLK` | records of the size the FCB holds, from and to the random record, which moves past them; `_WRBLK` with no records sets the file's size to the random record's — longer, with zeros, or shorter |

A program has five files open at once, whichever handles or FCBs it
uses for them; the sixth `_OPEN` or `_CREATE` is `.NHAND`. `_DUP` takes
no file of its own. A file has one writer at a time, on m6's side as on
the program's: `.FOPEN` for a second, and for a file a process of m6 has
open when the program starts. `_HRENAME` and `_HMOVE` close the file
behind the handle around the change and open it again, its position
kept.

## Files through FCBs

The CP/M-compatible functions work on the same files, through the same
five descriptors: an FCB opened by `_FOPEN` or `_FMAKE` takes one, and
`_FCLOSE` gives it back. A program that opens a sixth file through an
FCB without closing one does not fail: the FCB opened longest ago
loses its descriptor, and gets it back, on the same file, the next time
it is read or written — as a closed FCB does when it is used again,
which MSX-DOS allows. What the layer keeps in the FCB is what MSX-DOS 2
keeps there: the name as found, the attributes, the size, the extent's
record count; the bytes MSX-DOS calls internal say which descriptor and
where the file is.

What differs from MSX-DOS 2: a second FCB on a file another FCB or
handle writes gets it for reading only, since a file has one writer at
a time; `APPEND` is not consulted when a file is not found, the
environment being the program's own; the volume id written into the FCB
is never checked, there being no change of media to detect. Bytes `0Eh`
and `0Fh` are the record size for the block functions and the extent's
high byte and record count for the others, as in MSX-DOS 2: a program
that uses both on one FCB sets them again between.

Ctrl-C and Ctrl-STOP are checked at the console functions and end the
program with `.CTRLC` (`9Eh`) or `.STOP` (`9Fh`), through the abort
routine when one is defined. A program polling the keyboard itself is
not interrupted by anyone, as under MSX-DOS.

The errors are MSX-DOS 2's: what m6 refuses comes back as the nearest
MSX-DOS 2 code — a missing file `.NOFIL`, a missing directory `.NODIR`,
a full volume `.DKFUL`, a read-only file `.FILRO`, a file in use
`.FOPEN`, a name m6 cannot make `.IFNM`, a path too long for it `.PLONG`,
a disk error `.DISK` — and `_EXPLAIN` has the words for each.

## What is not there

- Absolute sector access, a RAM disk, `_FORMAT`, the Nextor functions.
- Long file names: the program works with 8.3 aliases.
- Volume labels, redirection of the standard handles, setting the clock.
- Anything of the BIOS's the machine does not have: m6 adds nothing to
  it and takes nothing from it.
