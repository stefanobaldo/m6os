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

At the keyboard the kernel does the line editing (BS, DEL, ^U, ^D), so a
line reaches the shell whole.

## Commands

The first word names the program: a word without `/` is a file in
`/bin`, so `cat` is `/bin/cat`; a word with one — `/t/tick`, `./x` — is
the path as written. The program gets the words as its arguments, the
first being the word typed, not the path.

A program that is not there is reported — `sh: nofile: ENOENT` — and the
line goes on.

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
open is reported and the command is not run.

## Lists and the background

`;` separates commands, or pipelines, that run one after the other. A
list that ends in `&` runs in the background: the shell prints its pid
as `[pid]` and takes the next line at once. When the job ends, the shell
reports it as `[pid] status` before its next prompt.

A background job does not take ^C from the keyboard. Only a `kill` ends
it, or its own end.

## Status

A command that ends with a status other than 0 is reported as `[N]`:
`[1]` for `false`, `[130]` for a command ^C ended, `[141]` for one that
wrote into a pipe nobody was reading, `[143]` for one `kill` ended —
128 plus the signal, as `waitpid` returns them. Nothing is printed for
a status of 0.

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

No variables, no `$?`, no `if` or `for`, no `PATH`, no history or
completion; a shell language is a program of its own, for later. A
pipeline of more than four commands, or a command of more than 31
words, is reported and not run.
