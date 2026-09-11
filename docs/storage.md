# Storage

What m6 does with the storage devices in the machine, from boot: which
volumes it finds, how it names them, and what it does not do yet.

## Drivers and devices

m6 uses the storage drivers the machine already has: the device-based
driver of every Nextor 2 cartridge, called directly at its fixed entry
points with the Nextor kernel out of memory. The program that starts m6
records every such driver it finds — up to four, in the order Nextor lists
them — and the kernel asks each one, at boot, which devices it has (1 to 7)
and which logical units each device has (1 to 7), keeping the units that
are block devices with 512-byte sectors. A unit whose driver flags it as
not to be mounted automatically is skipped with one line.

## Volumes

For every unit the kernel reads sector 0 and walks the partition table the
way Nextor does: the four primary entries in order, and, when one of them
is an extended partition (type `05h`), the chain of logical partitions
inside it — up to nine — before going on to the next primary entry. A
partition is a candidate when its type is FAT12 or FAT16 (`01h`, `04h`,
`06h`, `0Eh`), its numbers are sane (a first sector and a size, inside the
unit when the unit reports its size), and its first sector is a FAT boot
sector: 512 bytes per sector, a power of two of sectors per cluster, one to
seven FATs, root directory entries, and a sectors-per-FAT count that is not
zero — the whole 16-bit field counts, and a nearly full FAT16 volume fills
256 sectors with its table, while zero is what a FAT32 volume leaves there.
A partition that fails the last check is skipped with one line saying so,
never mounted "nearly". A unit with no partition of ours at all is tried as a
single FAT volume itself (a "superfloppy", the way an unpartitioned card
is formatted). FAT32 volumes are not mounted, as they are not under
Nextor. Extended partitions of type `0Fh`, which a PC writes, are not
walked either: Nextor does not walk them, and walking them would change
which letter a partition gets on a card Nextor also reads.

This is the layout Nextor's own FDISK creates — partition 1 primary,
every other partition logical inside an extended entry 2 — so a card
partitioned for Nextor shows every partition it shows there, and in the
same order.

## Names

Every volume is `/mnt/` and a letter: `a` for the first found, in the
order of the walk — drivers as listed, device 1 to 7, unit 1 to 7,
partitions in the order above — so that `/mnt/c` is the card's `C:` under
Nextor in the common case. The volume m6 was started from is also `/`,
whichever letter it got. At most eight volumes are mounted; a ninth gives
one line and is not. A letter is not stable across machines or cartridge
slots, any more than a Nextor drive letter is.

## The boot listing

Each volume prints one line as it is found:

```
/mnt/a  Sunrise IDE  1.1 p1  06  1048576 KB /
/mnt/b  Sunrise IDE  1.1 e1  01     2047 KB
/mnt/c  Sunrise IDE  2.1 --  01     2048 KB
```

The letter; the driver's name as the driver gives it; device and unit;
the partition — `p1` to `p4` a primary entry, `e1` to `e9` a logical one
in the chain, `--` a unit that is one volume; the partition type byte
(`00` for a superfloppy); the size in KB, the sector count halved; and
` /` on the boot volume. A device that answered but has no volume prints
one line saying so; a device that did not answer prints nothing.

## Reading and writing

Everything above the driver addresses a sector by volume, and a sector at
or past the volume's end is refused before the driver is called: nothing
in the kernel can reach the partition table or a neighbouring partition
through a volume. One sector moves per driver call, so the time a driver
keeps interrupts disabled stays inside one 60 Hz frame and the tick is
delayed, never lost. The kernel keeps a cache of 24 sectors, written
through: a write reaches the disk before the call that made it returns,
so there is nothing to flush and a card pulled after a call has everything
the call wrote. Whole, aligned sectors go from the driver straight into a
program's memory without a copy.

A driver error comes back as an error number and nothing is retried; a
write to a read-only unit is refused. A card changed while the system
runs is not noticed: until a reboot its volumes keep their letters and
every access returns an error.

## The clock

The real-time clock is read when a date is needed, as the FAT date and
time words a directory entry holds; the kernel keeps no clock of its own
and never sets the RTC. A machine without one reads 1980-01-01 00:00, and
so does a reading that is not a valid date and time — an unset chip or a
flat battery, which otherwise offers month 0 or hour 29 for a directory
entry to keep.

## Files

Every mounted volume is read as a FAT12 or FAT16 filesystem: the type is
decided by the number of clusters, as the specification says, never by
the label in the boot sector. The boot volume is `/`; every volume, the
boot one included, is `/mnt/` and its letter, so `/mnt/b/readme.txt` is a
file on the second volume and `/mnt` itself lists the letters as
directories. Inside a volume the paths are the usual ones: components
separated by `/`, `.` the directory itself, `..` its parent. `..` at the
root of a volume leads to `/mnt` — or to `/` on the boot volume — and
`mnt` is a real directory on every volume but at the root of the boot
volume, where the kernel's `/mnt` shadows it.

Names are FAT's short names: up to eight characters, a dot and up to three
more, matched without regard to case and listed in lower case. A long
name a PC wrote is not shown; the short name beside it is what the file
is called here, and the long-name entries are left as they are. A name
that does not fit the form names nothing.

Each process has a current directory, inherited by the processes it
creates and changed with `chdir`; a path that does not begin with `/`
starts there. A file is read through `open`, `read`, `lseek` and `close`,
a directory through `open` and `readdir`, and `stat` describes either;
`exec` starts a program from a file. [`syscalls.md`](syscalls.md) has the
calls, [`programs.md`](programs.md) the file a program is.

A whole sector read into a buffer that starts on a 256-byte boundary goes
from the driver straight into the program's memory; every other read goes
through the kernel's cache and a copy, at about 3.3 ms more per sector on
an MSX at 3.58 MHz. Sequential reads of whole sectors therefore run at the
driver's speed less the table lookups. Measured on an MSX2 at 3.58 MHz
reading a 64K file: about 89 KB/s through a driver that moves a sector in
4.8 ms, and about 77 KB/s through one that takes 5.4 ms. The kernel's own
share is about 0.8 ms per sector on either — the rest is the driver.

### Writing

Files are created with `open`, written with `write`, extended by writing
past their end, emptied with `O_TRUNC`, removed with `unlink` and renamed
with `rename`; directories are made with `mkdir` and removed, empty, with
`rmdir`. Every call that changes a volume finishes its work before it
returns: the data sectors first, then the allocation table — both copies,
so they never disagree — then the directory entry; a removal writes the
entry first and frees the clusters after. So a card pulled at any moment
holds, at worst, clusters that belong to no file, which a FAT checker
reports and reclaims, never a file pointing at free space, and there is
no cache to flush before the card is taken out. What one call costs: a
driver call per data sector (whole sectors from a buffer on a 256-byte
boundary go straight from the program's memory), two more for the table
when a cluster is allocated — once per call, however many clusters it
allocates — and one for the entry. A `write` of a few bytes into a sector
that already has data reads it, changes it and writes it back. Free
clusters are handed out next to the file's last one, so a file written in
one go is laid out contiguously; when the volume is full, `write`
returns what fitted and `ENOSPC` on the next call.

A file has one writer at a time, and a file that is open cannot be
removed or renamed; the read-only attribute is honoured and cannot be
cleared here. The modification time comes from the machine's clock when
a file is created and on every write; the directory's own time is not
touched, and long-name entries beside a removed or renamed file stay.
Making a directory zeroes its whole cluster — 8 sectors on a small
volume, 128 on a 4 GB one, where `mkdir` takes most of a second.

## Not yet

Long names are neither shown nor made; the read-only attribute cannot
be changed; a file's access date is never written; a `rename` across
volumes is refused. A card changed while the system runs is not noticed.
