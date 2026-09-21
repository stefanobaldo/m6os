# The shell

`sh` reads commands from its input, one line at a time, and runs them. It
is the Sixth Edition shell without its variables: words, pipelines,
redirection, lists, background jobs, wildcards, `cd` and `exit`. The
kernel starts it at boot — first on `/etc/rc`, if that file exists, then
at the keyboard — and starts it again whenever the one at the keyboard
exits.

## Lines and words

A line is at most 128 bytes and is cut into words on blanks and tabs.
`'...'` and `"..."` keep what is between them as it is, blanks included;
nothing is expanded inside either. `#` ends the line. A line longer than
128 bytes is reported and skipped.

At the keyboard the kernel does the line editing — the cursor keys, BS
and DEL, HOME and ^E, ^U, ^D, as [`syscalls.md`](syscalls.md) describes
under *The console* — so a line reaches the shell whole. ^L, or
SHIFT+HOME, clears the screen and leaves the prompt and the line at the
top.

## Earlier lines: UP and DOWN

At the prompt, UP brings back the last line run, ready to edit and run
with RET; UP again goes one line further back, DOWN one forward, and
DOWN past the newest line is the empty line again. A line brought back
is edited like any other, and stored as it ran. The shell keeps the last
sixteen lines, in memory: a line of no words is not stored, nor a line
the same as the one stored last, and the history is gone when the shell
exits or the machine is switched off. A command reading the keyboard in
the middle of a session sees UP and DOWN dropped, as always.

## Commands

The first word names the program: a word without `/` is a file in
`/bin`, so `cat` is `/bin/cat`; a word with one — `/t/tick`, `./x` — is
the path as written. The program gets the words as its arguments, the
first being the word typed, not the path.

A program that is not there is reported — `sh: nofile: ENOENT` — and the
line goes on.

A word ending in `.com`, in either case, names an MSX-DOS program:
when it is not a native command the shell runs it through `dos`
([`commands.md`](commands.md)), with the same arguments, so `ted.com
t.txt` at the prompt is `dos ted.com t.txt`. [`dos.md`](dos.md) says
what such a program gets.

## Pipelines

`|` joins commands into a pipeline: each one's output is the next one's
input, all of them running at once. A pipeline has at most four
commands, which is what a machine with 128K can hold beside the shell.

## Redirection

| Form | Effect |
|---|---|
| `< file` | the command reads the file as its input |
| `> file` | its output goes to the file, made or emptied first |
| `>> file` | its output is added at the file's end |
| `2> file` | its messages go to the file |

A redirection belongs to the command it follows; in a pipeline, `<` on
the first and `>` on the last are the usual ones. A file that does not
open is reported and that command is not run; the rest of the pipeline
still runs, the command after it reading an empty input and the one
before it ending on a broken pipe.

## Lists and the background

`;` separates commands, or pipelines, that run one after the other. A
list that ends in `&` runs in the background: the shell prints its pid
as `[pid]` and takes the next line at once. When the job ends, the shell
reports it as `[pid] status` before its next prompt. A shell reading a
script collects the jobs that ended before each line it reads, and
reports none of them: a report would land wherever the job happened to
end among the script's own output.

A background job does not take ^C from the keyboard. Only a `kill` ends
it, or its own end.

## Status

A command that ends with a status other than 0 is reported as `[N]`:
`[1]` for `false`, `[130]` for a command ^C ended, `[141]` for one that
wrote into a pipe nobody was reading, `[143]` for one `kill` ended —
128 plus the signal, as `waitpid` returns them. Nothing is printed for
a status of 0, nor for a command that could not be started: its
message — `sh: nofile: ENOENT` — is the whole report. A background
list prints its pid in the same brackets when it starts, not a status.

## Wildcards

A word holding `*` or `?` is matched against the names in its
directory: `*` is any run of characters, `?` one, without regard to
case. `r?` names `r1` and `r2`; `/t/*.txt` names the files of `/t` whose
name ends in `.txt`. The matches take the word's place in the order the
directory stores them; a word matching nothing stays as it is. Only the
last component of a path is matched, and a quoted word never is.

## cd and exit

`cd dir` makes `dir` the current directory; `cd` alone goes to `/`.
`exit` ends the shell, with status `n` when written `exit n`. Everything
else the shell runs is a program in `/bin`.

## Interactive or not: -i

Started as `sh -i`, the shell is interactive: before each line it
reports the jobs that ended, puts the terminal in canonical mode and
prints a prompt — the current directory and `$ `. It ignores ^C, so
that ^C ends the command in the foreground and the prompt comes back.
This is the shell the kernel starts at the keyboard.

Started as `sh`, it reads its input silently to the end, and ^C ends it
along with the command it was running. This is what runs a script:
`sh < file`, and `/etc/rc` at boot. A script's commands share the
script as their input, so one that reads its input without a file or a
pipe — `cat` alone — reads the rest of the script.

## What is not there

No variables, no `$?`, no `if` or `for`, no `PATH`, no completion, no
history file; a shell language is a program of its own, for later. A
pipeline of more than four commands, or a command of more than 31
words, is reported and not run.
