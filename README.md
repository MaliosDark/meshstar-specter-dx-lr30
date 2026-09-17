# MeshStar relay for the DX-LR30

Firmware that turns the **DX-LR30** repeater (STM32F103C8T6 +
SX1262, 64 KB flash, 20 KB RAM) into a **MeshStar relay**: a node of the
[MeshStar](https://github.com/MaliosDark/MeshStar) LoRa mesh that extends
the network's reach without originating or reading any traffic.

Written in Rust (`no_std`), no RTOS, no Arduino. The whole firmware is
45 KB of flash and uses 10 KB of RAM.

## What a MeshStar relay is

MeshStar routes with ZRP (zone routing: proactive tables two hops around
each node, reactive discovery beyond) over Noise XX end-to-end sessions.
A relay runs the forwarding half of a node:

* sends **beacons** and keeps the neighbour, zone and route tables like
  any node (so its neighbours see through it);
* relays **ROUTE_REQUEST** floods with the storm rules (jitter, counter
  cancel, density-based probability) and coverage pruning;
* forwards **unicast** packets it is the next hop of, with hop-by-hop
  reliability: implicit acknowledgement, `LINK_ACK`, two retries, reroute
  through another neighbour, `ROUTE_ERROR` back to the source when all
  fails;
* repairs routes on behalf of a source when its own table has none;
* floods broadcast data with the same storm rules;
* holds a couple of packets for a sleeping LEAF neighbour until it beacons.

It has no sessions, no mailbox, no transport, no fragmentation and no
keys: **it never decrypts anything**. MeshStar's packet design allows
this: only `ttl`, `hops`, `next_hop` and `relay` are mutable per hop; the
rest is bound by the authenticated encryption between the two ends.

The engine lives in the MeshStar repository (`meshstar_core::relay`) and
mirrors the full node's rules, frame formats and tables, so relays and
nodes interoperate; an integration test there proves two nodes out of
range of each other talk through one relay.

### What does not fit in 64 KB, and what that means

| build | flash |
|---|---|
| full MeshStar node (ANCHOR role) on Cortex-M3 | 172 KB |
| relay engine with Ed25519 signing and verification | 114 KB |
| relay with an unsigned identity, no signature verification, SplitMix RNG | 77 KB |
| same, with the protocol tables on sorted `Vec`s instead of `BTreeMap` | 41 KB |
| **this firmware** (HAL, SX1262 driver, console included) | **45 KB** |

Stated plainly: on this part the relay does **not sign its beacons** and
does **not verify others'**. Its address is derived from the MCU's unique
id, not from a key. MeshStar nodes only need a neighbour's *proven*
identity for sessions and envelopes, which never involve a relay, so an
unsigned relay is a routing label, exactly like any node between its
periodic signed beacons. On a bigger MCU the same engine runs with a
signed identity and behaves like a node.

## Hardware

| Function | STM32 pin | Notes |
|---|---|---|
| SPI1 SCK / MISO / MOSI | PA5 / PA6 / PA7 | 4 MHz, mode 0 |
| NSS | PA4 | driven by the radio driver |
| BUSY | PA2 | |
| NRST | PA3 | |
| TXEN / RXEN | PA0 / PA1 | RF switch, driven around every transmission |
| DIO1 | not wired | IRQ status polled over SPI |
| LED | PB11 | on at boot, blinks per frame received/sent |
| USART1 TX / RX | PA9 / PA10 | console, 115200 8N1, through the CH340 |

Oscillator: the module has a plain crystal. The firmware tries a DIO3
TCXO (RadioLib's default assumption) first and falls back to XTAL when the
test transmission at boot times out; the console reports which one is in
use.

Radio profile: MeshStar EU868 default, 869.525 MHz, 125 kHz, SF8, CR 4/5,
sync word 0x1A, 32-symbol preamble, 14 dBm.

## Build

```
rustup target add thumbv7m-none-eabi
rustup component add llvm-tools
pip install stm32loader pyserial
cargo build --release
```

The MeshStar crates (protocol core and SX126x driver) come from a
MeshStar checkout next to this folder: `git clone
https://github.com/MaliosDark/MeshStar ../MeshStar`. `Cargo.toml` shows
how to point at GitHub directly instead.

## Flash

The DX-LR30's CH340 has no DTR/RTS wiring, so the STM32 ROM bootloader is
entered by hand and talks at **57600** baud on this board:

1. Hold **BOOT0**, press and release **RESET**, release **BOOT0**.
2. `./flash.sh /dev/ttyUSB0` (builds, converts to `.bin`, erases, writes,
   verifies).
3. Press **RESET**.

`flash.sh` uses `stm32loader`; `stm32flash -w target/relay.bin -v -b 57600
/dev/ttyUSB0` works as well.

If the port opens with `Input/output error` and the kernel log shows
`failed to receive control message: -110`, the USB controller is not
talking to the CH340 (seen with an add-on PCIe USB card): use a port on
the motherboard.

## Console

At boot:
```
MeshStar relay MS-f703d7e2ff91228f (Specter DX-LR30)
radio: attempt failed err 1
radio: SX1262 ok (XTAL)
```
then every 30 s:
```
relay up=180 nb=2 zone=2 routes=2 rx=23 tx=3 relayed=1 rreq=0 beacons=1 retx=0 bad=0 rssi=-24 rxerr=0 lasterr=0 cad=16
```
`nb` neighbours heard, `zone` nodes within two hops, `routes` cached
routes, `rx`/`tx` frames, `relayed` frames forwarded, `rreq` route
requests re-flooded, `beacons` sent, `retx` hop-by-hop retransmissions,
`bad` undecodable frames, `rssi` of the last frame, `cad` listen-before-
talk hits.

Validated with the board next to two Heltec V3 MeshStar nodes: it heard
and decoded both (`nb=2 rx=23 bad=0`), re-flooded one broadcast and
pruned the rest by coverage (correct when everybody hears everybody). With
the two nodes out of each other's range, traffic goes through the relay
(the case the integration test covers).

## Layout

```
src/main.rs   board bring-up (clocks, SysTick, SPI, UART, GPIO), RF switch
              wrapper, console without core::fmt, the relay loop
memory.x      64 KB flash / 20 KB RAM
flash.sh      build + flash through the ROM bootloader
```

## License

GPL-3.0
