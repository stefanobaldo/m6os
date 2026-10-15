# The m6 block device

A register block a storage cartridge may present beside its own
registers, through which a cartridge that is itself the machine's memory
mapper moves sectors between its medium and that RAM with the CPU moving
nothing — the **Turbo** transfer mode — and answers a few questions about
a FAT table on its medium. This document is the specification a
cartridge maker implements; m6's drivers use the block where they find
it, and run as before where they do not.

The block is independent of what else the cartridge presents. The first
drivers to use it are m6's SD driver (`docs/drivers.md`), on a cartridge
that presents the SD Mapper V2's register set beside the block, and a
reference implementation exists in the project's openMSX fork, which is
what the tests run on. A ROM never creates a capability: the block exists
where the cartridge's logic decodes it, and nowhere else.

## Where

Sixty-four bytes at `7F00h`–`7F3Fh` of page 1 of the cartridge's slot,
decoded at least while the driver bank of the kernel ROM is selected
(bank 7 of an ASCII16 ROM); a cartridge may decode them in every bank.
The address collides with none of the registers the known cartridges
decode — the SD Mapper V2's SPI window at `7B00h`–`7EFFh` and its
registers at `7FF0h` and above, the Sunrise IDE's at `7C00h`–`7EFFh`, the
ASCII16 bank registers, the kernel ROM's bank switch at `7FD0h` — and a
cartridge without the block shows the ROM's own bytes there, which the
kernel ROM fills with `FFh`, so they never read as the signature.

## The registers

`r` is read by the driver, `w` written by it. The device never changes a
`w` register; reading one is undefined.

| Offset | | Content |
|---|---|---|
| 0–3 | r | the signature, `"M6BD"` |
| 4 | r | the version, 1 |
| 5 | r | capabilities: bit 0 Turbo offered; bit 1 the FAT accelerator's commands answer; bit 2 reserved (a data window), 0; bits 5–4 the subslot of the cartridge's own slot holding the memory mapper the device serves; bit 7 the device serves a mapper there |
| 6 | r | devices the block answers for, 1–N |
| 7 | w | the device of the next command, 1–N |
| 8–11 | w | the first sector, little-endian |
| 12 | w | sectors, 1–32 |
| 13 | w | the target segment |
| 14 | w | the target's 256-byte slot in the segment, 0–62: the target is `segment × 4000h + slot × 100h` of the device's RAM |
| 15 | w | the probe byte |
| 16 | w | the command; the write starts it |
| 17 | r | `80h` while the command runs; `00h` done; `01h`–`7Fh` an error |
| 18–21 | r | a 32-bit result, little-endian |
| 22–63 | w | parameters of commands that take more than the above; 0 for the commands below |

Commands: `01h` read (medium → RAM), `02h` write (RAM → medium),
`10h`–`13h` reserved for the FAT accelerator, `80h`–`FFh` the device's
own. Errors: `01h` the probe byte is not at the target (nothing moved),
`02h` out of range, `03h` the medium failed, `04h` no medium, `05h` the
medium is write-protected, `06h` a bad parameter (a count of 0 or above
32, a slot past the page, a device of 0 or above the count), `07h` an
unknown command.

## Turbo

A device that offers Turbo is, or serves, a memory mapper of the MSX
kind — segments of 16K selected into the four pages through ports
`FCh`–`FFh`, segment `n` of the mapper being bytes `n × 4000h` up of the
device's RAM — in a subslot of the cartridge's own slot, which the
capabilities name. Turbo is in force only when that mapper is the
machine's primary one, the mapper every process page comes from; m6's
kernel ROM makes it so at boot when the BIOS has not (it moves page 3
into the device's mapper), and tells the driver through its `DQ_MODE`
query. A device that offers Turbo gives its user a way to stop offering
it: a machine whose own mapper is larger than the cartridge's gives that
capacity up for Turbo, and the choice is the user's.

A read: the driver writes the device, the first sector, the count, the
target segment and slot, and a probe byte it has put at the target, then
the command. The device compares the byte at the target with the probe
before anything moves, refuses with error `01h` when they differ — the
target is not in its RAM — and otherwise writes `count × 512` bytes at
the target from the medium. The command is done, and the status reads
`00h`, when every byte is in RAM; until then the target holds its old
bytes. A write is the same with the direction reversed: the probe byte
is the target's first byte, and the command is done when the medium has
every byte — a device keeps no write cache of its own, so a card pulled
after the call has what the call wrote. A command never crosses the
16K segment: `slot + 2 × count ≤ 64`.

The driver polls the status with interrupts enabled; the device never
asserts an interrupt. The driver writes no register while the status
reads `80h`. Throughout a command the device keeps serving the bus for
its mapper: the kernel, its interrupt handler and the polling loop all
run from that RAM meanwhile.

A driver falls back on its own transfer path when the probe is refused,
which is what lets Turbo become a per-page matter on a machine where
process pages live in more than one mapper.

## The FAT accelerator

Reserved: commands `10h`–`13h`, their parameters in the block's last
forty-two bytes, their results in the result register. They answer
questions about a FAT table on the device's medium — a count of free
clusters from a given one, the next free from a given one — with the
table's geometry carried in every command, so the device keeps nothing
between commands. Their definition follows in a later version of this
document; a device that does not answer them leaves capability bit 1
clear.
