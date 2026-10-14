# Storage drivers

How m6 talks to a storage device, and what a driver written for m6 looks
like. There are two kinds of driver:

- **A Nextor 2 driver**, the one every Nextor cartridge already carries
  in its kernel ROM. m6 calls it through its legacy adapter, the way it
  has always called it: one sector per call, with interrupts disabled for
  the length of each sector. This is what M6.COM and NEXTOR.SYS use, and
  what the kernel ROM uses when it is built from a cartridge's own Nextor
  ROM.
- **A driver block**, written to the contract below. It lives in the
  driver bank of an m6 kernel ROM, moves up to 32 sectors per call, and
  runs with interrupts enabled, so the clock keeps ticking and the
  keyboard keeps answering while a transfer is in progress. A driver
  block exists only in a kernel ROM: a machine booted through M6.COM or
  NEXTOR.SYS has Nextor's ROM in the cartridge, and its driver is always
  the Nextor one. m6 ships one such block, `m6ide`, for the Sunrise IDE
  (below).

The rest of this document is the contract a driver block is written to,
then the driver m6 ships.

## Where a block lives

A kernel ROM is eight banks of 16K. Bank 7 is the driver bank: either
the Nextor kernel ROM's own driver bank, taken whole, or a driver block
at `4100h` of that bank, behind the bank's 24-byte cartridge header. The
bank switch at `7FD0h`, present in every bank, comes from the cartridge's
Nextor kernel ROM in both cases. A block may be up to `3ED0h` bytes long
(`7FD0h` − `4100h`).

```
make rom-from DRIVER_ROM=<the cartridge's Nextor kernel ROM> DRIVER=<block.asm>
```

builds such a ROM, `build/m6-<ROM>-<block>.rom`, and prints the room
left in its driver bank; `make rom` builds the Sunrise IDE ROM this way
with `src/drivers/m6ide.asm`. The source is assembled for `4100h` with
`src/kernel/kernel.inc` already included, so it names everything below
by its symbol. It is assembled inside the ROM's own source, so its labels
share the ROM's: prefix them with the driver's name, as `m6ide`'s `si_`
does, or wrap the block in a `MODULE`. The ROM's resident kernel is
built without the legacy adapter.

A cartridge whose registers appear in page 1 in place of part of the ROM
while they are enabled — the Sunrise IDE's at `7C00h`–`7EFFh` — bounds
the block below them: its code is unreadable there while a transfer
runs. Such a block ends with an assertion on its own end address.

## The block header

At `4100h`, 48 bytes:

| Offset | Size | Symbol | Content |
|---|---|---|---|
| 0 | 5 | `DRV_SIGN` | `"M6DRV"` |
| 5 | 1 | `DRV_VER` | `DRV_VER_1` (1) |
| 6 | 1 | `DRV_FLAGS` | `DF_TURBO` (1) when the device can take a Turbo target; the other bits 0 |
| 7 | 3 | `DRV_INIT` | `jp` to init |
| 10 | 3 | `DRV_INFO` | `jp` to info |
| 13 | 3 | `DRV_STATUS` | `jp` to status |
| 16 | 3 | `DRV_RW` | `jp` to the transfer |
| 19 | 3 | `DRV_QUERY` | `jp` to query |
| 22 | 3 | `DRV_RES1` | `jp` to a routine returning CF set and `A` = `E_NOSYS` |
| 25 | 3 | `DRV_RES2` | the same |
| 28 | 2 | `DRV_RAM` | bytes of RAM the block wants, 0 to `DRV_RAM_MAX` (576) |
| 30 | 2 | `DRV_RELOC` | 0 |
| 32 | 16 | `DRV_NAME` | the block's name, space padded |

A ROM whose bank 7 holds a block of a version this kernel does not know
does not boot. It prints `m6: boot failed, code F6` and returns to BASIC.

## The block's RAM

A block is ROM, and keeps no variable in its own bank. At boot the
kernel ROM takes `DRV_RAM` bytes from just below `F380h`, the start of
the BIOS work area, clears them, and enters every routine of the block
with `IX` pointing at them. They lie above the resident kernel and below
the BIOS work area. A block that asks for more than 576 bytes makes the
boot fail with code `F5`.

## How the kernel calls a block

For every call, the kernel:

1. selects the cartridge's slot in page 1 and the driver bank in it, so
   the block runs at its own address, with the cartridge's registers in
   view;
2. maps into page 2 the segment the call is about (below);
3. leaves page 0 as the running process has it, with the interrupt
   vector at `0038h`;
4. runs the call on the kernel's stack, in page 3;
5. enables interrupts, loads the registers below, and calls the entry.

When the entry returns, the kernel puts page 1 back to RAM and page 2 as
it was. The kernel never calls a block while a call into any driver is in
progress: a block may assume it is the only driver running.

A block corrupts any register but `SP` and `IX`, the alternate set and
`IY` included. It leaves `IM` and `I` as they are. It returns with
interrupts enabled. On return `CF` and `A` carry the result, `B` the
block's own code, and `HL` and `DE` what the entry says.

## The entries

### init

Called once, at boot, before the kernel looks for volumes. Page 2 is
the kernel's storage segment, which init does not write. `IX` points at
the block's RAM, cleared.

- Out, success: `CF` clear, `A` = the highest device number the block
  serves, 1 to 49. Devices are numbered from 1; info may answer that a
  number below that is no device.
- Out, failure: `CF` set, `A` = a code of the block's own. The kernel
  prints `driver 0: init failed` and never calls the block again.

### info

Describes a device. Page 2 is the storage segment.

- In: `A` = device; `HL` → a 64-byte buffer in page 2.
- Out: `CF` clear and the buffer filled; or `CF` set and `A` = `E_NXIO`
  when there is no such device. Nothing else in page 2 is written.

| Offset | Size | Symbol | Content |
|---|---|---|---|
| 0 | 1 | `DI_FLAGS` | bit 0 removable, bit 1 read-only, bit 2 floppy, bit 3 do not mount automatically — the bits of Nextor's `LUN_INFO` — and bit 7 no medium |
| 1 | 1 | `DI_CAPS` | bit 0 Turbo, bit 1 the FAT accelerator's queries; the rest 0 |
| 2 | 4 | `DI_COUNT` | sectors of 512 bytes; 0 when unknown or with no medium |
| 6 | 1 | `DI_TSLOT` | the slot of the mapper a Turbo device writes into; 0 none |
| 7 | 1 | | 0 |
| 8 | 32 | `DI_NAME` | the name the boot listing prints, space padded |
| 40 | 16 | `DI_IDENT` | the device's identity: bytes 0–3 its slot, its device number as Nextor would give it, its unit as Nextor would give it (1 when the device has none), and 0; bytes 4–15 the block's own, such as a serial number |
| 56 | 8 | | 0 |

The kernel finds the volume it was started from by comparing the first
three identity bytes with what the loader recorded. A block for hardware
a Nextor driver also serves gives the slot, device and unit that driver
would give.

### status

- In: `A` = device. Page 2 is the storage segment.
- Out: `CF` clear and `A` = 0 not available, 1 unchanged, 2 changed, 3
  unknown — the values of Nextor's `DEV_STATUS` (`DS_NOTAVAIL`,
  `DS_SAME`, `DS_CHANGED`, `DS_UNKNOWN`); or `CF` set and `A` = `E_NXIO`.

### rw

The transfer.

- In: `A` = device; `CF` = 0 read, 1 write; `B` = sectors, 1 to 32; `C`
  = the target's slot in page 2, 0 to 62; `DE:HL` = the first sector
  number, `DE` high. Page 2 is the target segment, and the data starts at
  `8000h` + `C` × 256. The kernel never asks for more than fits in the
  page: `C` + 2 × `B` ≤ 64.
- Out: `CF` clear and `A` = 0; or `CF` set and `A` = `E_IO` (5),
  `E_NXIO` (6) or `E_ROFS` (30). In both, `B` is the block's own code, 0
  for none, which the kernel keeps for diagnostics.
- On a read the block writes exactly `B` × 512 bytes from `8000h` + `C`
  × 256, and nothing else in page 2. On a write the bytes there stay as
  they are for the whole call, and the block does not write them. A
  failed call says nothing about which sectors were moved.

Side by side with the call a Nextor driver gets, `DEV_RW`:

| | Nextor `DEV_RW` | m6 `rw` |
|---|---|---|
| device | `A` | `A` |
| unit | `C` | none: a device has no units |
| direction | `CF` | `CF` |
| sectors | `B` | `B`, 1 to 32 |
| buffer | `HL`, any address | page 2, at `8000h` + `C` × 256 |
| sector number | `DE` → 4 bytes | `DE:HL`, by value |
| interrupts | disabled | enabled |
| result | `A` = a Nextor error code | `A` = an m6 error number, `B` = the block's code |

### query

Anything else the device can do.

- In: `A` = device; `B` = the query's number; `HL` → its parameter
  block in page 2, whose layout the number defines.
- Out: as the number defines; `CF` set and `A` = `E_NOSYS` (38) for a
  number the block does not answer.
- Numbers `00h`–`7Fh` belong to the contract: `01h`–`04h` the FAT
  accelerator (`DQ_FATCOUNT`, `DQ_FATNEXT`, `DQ_FATWALK`, `DQ_FATFREE`)
  and `10h` the transfer mode (`DQ_MODE`), whose parameter blocks are not
  defined yet; the rest are reserved. Numbers `80h`–`FFh`
  (`DQ_PRIVATE` up) are the block's own.

## What a block may use of the kernel

| What | Where |
|---|---|
| The tick count, 60 a second | the word at `K_TICKS` (`C006h`) |
| The segment page 2 holds during rw, for a device that writes into the mapper itself | `call K_API2+3*API2_DRV_TGTSEG` → `A` |
| Its RAM | `IX`, at every entry |

Nothing else. A block never calls the BIOS: page 0 is the running
program's, not the BIOS. It never writes the slot or the mapper
registers: the kernel put page 1 and page 2 where they are.

## The rules

1. Run on the kernel's stack and never move `SP`. Use at most
   128 bytes of it, the handler's own use not counted.
2. Write no slot register and no mapper register.
3. Disable interrupts for at most 100 µs at a time, and return with them
   enabled.
4. Write nothing to the screen, and call nothing of the BIOS.
5. Write page 3 only inside the block's own RAM; read it only there, at
   `K_TICKS`, and through `K_API2`.
6. Write page 2 only as rw says, and page 0 never.

## While a block runs

The interrupt handler runs during a call — that is the point of enabling
interrupts. It counts the tick, scans the keyboard and queues a
CTRL+C. It never switches page 1 or page 2 and never hands the CPU to
another process while a driver call is in progress. A switch that comes
due is paid when the system call returns, and a signal is delivered at
that return, after the transfer has finished.

## The Sunrise IDE driver

`src/drivers/m6ide.asm` is the block `build/m6-sunriseide.rom` carries,
written from the ATA specification for the Sunrise IDE interface and
the cartridges compatible with it (a Carnivore2). It serves the master
as device 1 and the slave as device 2, each an ATA device addressed by
LBA: an ATAPI device, or a device without LBA, is treated as absent.

At boot it selects each position and waits for it to be ready, with a
soft reset of the bus only when neither position answers; a position
that answers is asked to `IDENTIFY`, and its model becomes the device's
name in the boot listing, its serial number part of the device's
identity, its sector count the device's size. A controller with no
device at all is listed once, as `Sunrise IDE` with no volumes.

A call of up to 32 sectors is one `READ SECTORS` or `WRITE SECTORS`
command; the driver waits for each sector with interrupts enabled and
moves it with an unrolled `LDI`, the fastest copy the Z80 has. Nothing
in the block disables interrupts. Every wait on the device is bounded
by the kernel's tick — two seconds on a command, five after a reset —
and a device that fails a transfer returns `E_IO` with the device's
error register, or its status when it timed out, as the block's own
code.

`build/m6-sunriseide-legacy.rom` is the same kernel ROM with the
cartridge's Nextor driver bank and the adapter instead, the way every
kernel ROM was built before this driver existed; it boots the same
card at the Nextor driver's speed, one sector per call with interrupts
disabled for each.

## The SD driver

`src/drivers/m6sd.asm` is the block `build/m6-sdmapper.rom` carries,
written from the SD specification for the FBLabs SD Mapper V2 and the
cartridges that present its register set — the MSX-Pico+ among them.
It is two files: `src/drivers/sdspi.asm`, the SD protocol in SPI mode
with nothing of the cartridge in it, and the port, which gives the core
the cartridge's SPI window, its card select and sense register, and the
512-byte copy through the window, as a handful of macros the core
expands. A driver for another SD cartridge is another port around the
same core.

The two card slots are devices 1 and 2, both removable. At boot each
slot is brought up at the cartridge's clock — `CMD0`, `CMD8`, `ACMD41`,
`CMD58` for the capacity class, `CMD16` on a standard-capacity card —
and asked for its CSD and CID: the card's sector count becomes the
device's size, its product name, revision and class (`SDHC` or `SDSC`)
the device's name in the boot listing, its serial number part of the
identity. An empty slot is a device with no medium, listed as such;
a card the driver cannot bring up is one too, and the step that failed
is kept in the driver's record, which `query` number `80h` returns. A
card that is not an SD card (an MMC) is not supported.

A call of up to 32 sectors is one `CMD18` ended by `CMD12`, or one
`ACMD23` and `CMD25` ended by the stop token; one sector is `CMD17` or
`CMD24`. Every response is read within eight bytes, every data token
and every busy is bounded by the kernel's tick — 100 ms for a token,
500 ms for a write's busy, one second for a card to become ready — and
nothing in the block disables interrupts: the window's exchange is one
bus cycle, and a card waits as long as the bus does between two bytes.
A transfer the card refuses returns `E_IO` with the card's own byte —
its `R1`, a data error token, a data response — as the block's code;
one the card refuses partway is closed first, `CMD18` with `CMD12` and
`CMD25` with the stop token, and the card's busy waited out, so the
next call finds the card ready.

The sense register is read at the start of every `rw` and `status`. A
card whose write-protect switch is on is listed read-only and refuses
writes with `E_ROFS` before any traffic. A card that was taken out
since the driver initialised it — the register's latch — answers
`E_NXIO` to every transfer until `status` is asked for that device,
which re-initialises the slot and answers `DS_CHANGED` (or
`DS_NOTAVAIL` when the slot is empty now); a card put into a slot that
was empty at boot is found the same way. The kernel does not ask
`status` on its own yet, so a card changed while the system runs is
refused until the next boot: nothing of a volume mounted from the old
card reaches the new one.

`build/m6-sdmapper.rom` is built from Nextor's standalone ASCII16
kernel ROM, whose bank switch is byte for byte the SD Mapper's and the
MSX-Pico+'s, so the native SD ROM needs no file of the cartridge's
maker; `build/m6-sdmapper-legacy.rom` is the kernel ROM built the way
every ROM was before this driver, from the cartridge's own kernel ROM
(Nextor with the SDXC driver, which `make fetch` downloads): the driver
bank taken whole, called through the adapter, both SD slots served.
