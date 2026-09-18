# MSX-DOS programs

m6 runs MSX-DOS 2 programs — `.COM` files — one at a time, each with the
machine to itself: the MSX-DOS 2 layout around it, the BIOS live, the
MSX-DOS 2 function calls served by m6 over its own files. When the
program ends, m6 is back where it was, with every process it had
suspended still there. This document says how to run one, what the
program finds, and what of MSX-DOS 2 is there and what is not.

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
program that ended with `_TERM` and code 7, `[159]` (`9Fh`) for one that
Ctrl-C ended.

While the program runs, nothing else does: m6's clock stands still, a
process asleep wakes late by the program's run, and a background job
waits. On a 128K machine the program needs every free segment — the
three pages of its TPA and one more for what is above it — so `dos` is
refused with `ENOMEM` while another process besides the shell is alive.

## What the program finds

The program is loaded at `0100h` and finds MSX-DOS 2 around it, as the
Program Interface Specification describes it:

- A TPA of 53K, from `0100h` to `D006h`, the `JP` at `0005h` that is the
  BDOS entry and the top of the TPA. This is a little less than Nextor
  gives (`DC06h` at its prompt), and what the specification calls
  "typically 53K".
- Page 0 as the specification lays it out: the warm-boot jump at `0000h`
  into a CP/M BIOS jump table, `RDSLT`, `WRSLT`, `CALSLT`, `ENASLT` and
  `CALLF` at `000Ch`–`0030h`, the interrupt vector at `0038h`, the two
  unopened FCBs at `005Ch` and `006Ch` built from the first two words of
  the tail, and the tail itself at `0080h`, upper-cased, with its length
  before it.
- The BIOS, live: every ROM routine reachable through `CALSLT`, the
  interrupt handler scanning the keyboard and counting `JIFFY`, `H.TIMI`
  and the other hooks the program may set. The console functions go
  through `CHPUT`, `CHGET` and `CHSNS`, so what the BIOS does with escape
  sequences and the cursor, the program gets.
- The mapper support routines, found through `EXTBIO` (`D` = 4, `E` = 1
  for the variable table, `E` = 2 for the jump table) as under MSX-DOS 2:
  `ALL_SEG`, `FRE_SEG`, `RD_SEG`, `WR_SEG`, `CAL_SEG`, `CALLS`, `PUT_Pn`
  and `GET_Pn` for pages 0–2. A segment the program allocates is freed
  when it ends. On a 128K machine with a shell up there is none to give.
- `_DOSVER` answers kernel 2.31 and MSXDOS2.SYS 2.31. m6 is not Nextor
  and does not answer Nextor's handshake, so a program takes its MSX-DOS 2
  paths; the Nextor functions (`71h`–`7Eh`) are refused.
- `EXTBIO` answers the mapper support and nothing else: a program probing
  for another extension gets its registers back untouched, which is the
  "absent" answer.

## The functions

The table says what each MSX-DOS 2 function does under m6. Functions not
in it, and the Nextor ones, return `.ISBFN` (invalid function number,
`DCh`).

| Function | Under m6 |
|---|---|
| `00h` `_TERM0`, `62h` `_TERM` | ends the program; the code in `B` is the status the shell reports |
| `01h` `_CONIN`, `07h` `_DIRIN`, `08h` `_INNOE` | a key from the BIOS, echoed by `_CONIN` only |
| `02h` `_CONOUT`, `09h` `_STROUT` | to the screen through the BIOS |
| `06h` `_DIRIO` | direct console I/O, as specified |
| `0Ah` `_BUFIN` | a line: BS and DEL take a byte back, RET ends it; no history |
| `0Bh` `_CONST` | whether a key waits |
| `0Ch` `_CPMVER` | `0022h` |
| `2Ch` `_GTIME` | the clock's time |
| `63h` `_DEFAB` | the abort routine, called when the program ends |
| `65h` `_ERROR` | the last error code |
| `66h` `_EXPLAIN` | the message for a code; `Error nnH` for one m6 does not know |
| `6Fh` `_DOSVER` | 2.31, not Nextor |

Ctrl-C and Ctrl-STOP are checked at the console functions and end the
program with `.CTRLC` (`9Fh`) or `.STOP` (`9Eh`), through the abort
routine when one is defined. A program polling the keyboard itself is
not interrupted by anyone, as under MSX-DOS.

## What is not there

- The file and directory functions, and the FCB functions: coming.
- A RAM disk, `_FORMAT`, redirection, the Nextor functions.
- Anything of the BIOS's the machine does not have: m6 adds nothing to
  it and takes nothing from it.
