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
seven FATs, root directory entries, sectors per FAT below 256. A partition
that fails the last check is skipped with one line saying so, never
mounted "nearly". A unit with no partition of ours at all is tried as a
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
and never sets the RTC. A machine without one reads 1980-01-01 00:00.

## Not yet

There is no filesystem yet: no files, directories, `open` or `read` on a
volume. Those come next, on top of what this document describes.
