# Casio FP-1100 — Notas de hardware para el core FPGA

Fuentes: driver MAME `casio/fp1100.cpp` (A. Salese), emulador eFP-1100 de
Takeda Toshiya (CSCP, `vm/fp1100/`), core uPD7800 de David Hunter
(SuperCassetteVision_MiSTer) y proyecto FP-1100_SD (yanataka60).

> Estado de los emuladores de referencia: MAME lo marca `MACHINE_NOT_WORKING`
> (teclado roto, handshake main↔sub incompleto). **El de Takeda funciona**
> (BASIC, cinta, disco) y es la referencia principal, aunque tiene dos
> "ugly patches" en el handshake que hay que resolver en hardware (ver §7).

---

## 1. Visión general

| Bloque | Chip | Reloj |
|---|---|---|
| CPU principal | Z80A | 3.9936 MHz (XTAL 15.9744 / 4) |
| CPU sub (vídeo, teclado, CMT, printer) | NEC uPD7801G (uPD7800 + 4 KB ROM + 128 B RAM internos) | 3.9936 MHz entrada → 1.9968 MHz ciclo máquina |
| CRTC | HD46505SP (6845) | 1.9968 MHz (80 col) / 0.9984 MHz (40 col) |
| RAM principal | 64 KB DRAM | — |
| VRAM | 3 × 16 KB (B, R, G) — FP-1000 solo 16 KB (mono) | — |
| ROM Z80 | 32 KB IPL + 4 KB BASIC ext (`basic.rom`, 36 KB) | — |
| ROM sub | 4 KB interna (`sub1.rom`) + 4 KB externa (`sub2.rom`) + chargen (`sub3.rom`) | — |
| Vídeo | 640×200 (8 colores) / 640×400 entrelazado; 40/80 col | dot clock 15.9744 MHz |
| Sonido | beeper en el teclado (bit 4 de E400) | — |
| Cinta | FSK 1200/2400 Hz, 300 o 1200 baudios, vía SIO del 7801 | 76.8 kHz base |

Timing de vídeo (Takeda): 128 chars/línea × 8 px = 1024 dots/línea a 15.9744 MHz →
64.1 µs/línea (15.6 kHz), 261 líneas/frame → **59.77 Hz**. Es un vídeo 15 kHz estándar.

## 2. ROMs

| Fichero | Tamaño | SHA1 | Uso |
|---|---|---|---|
| basic.rom | 36864 (0x9000) | 985757b9…10ec3 | Z80: 0x0000–0x8FFF (IPL 32K + BASIC 4K) |
| sub1.rom | 4096 | 917d5b39…c2a3 | uPD7801 ROM interna 0x0000–0x0FFF |
| sub2.rom | 4096 | 0188d5a7…28d7 | sub 0x1000–0x1FFF |
| sub3.rom | 3968 (0xF80) | a9ae6b03…9672 | chargen, sub 0xF000–0xFF7F (usado desde 0xF400) |

Los hashes coinciden con el set de MAME. `roms/fp1100.rom` es la concatenación
`basic + sub1 + sub2 + sub3 + 128×00` = 49152 bytes (0xC000), pensada para
cargarla de una vez por el ioctl/OSD y repartirla por offset:

```
0x0000-0x8FFF  basic.rom  → ROM Z80
0x9000-0x9FFF  sub1.rom   → ROM interna 7801 (INIT_SEL_BOOT del core)
0xA000-0xAFFF  sub2.rom   → ROM sub 0x1000
0xB000-0xBF7F  sub3.rom   → chargen 0xF000
```

## 3. CPU principal (Z80) — mapa de memoria

Bit 1 de OUT 0xFFA0 (`rom_sel`, 0 al reset = ROM visible):

| Rango | ROM visible (rom_sel=0) | RAM (rom_sel=1) |
|---|---|---|
| 0x0000–0x7FFF | IPL ROM (lectura); **escrituras siempre a RAM** | RAM |
| 0x8000–0x8FFF | BASIC ROM ext (lectura); escrituras a RAM | RAM |
| 0x9000–0xFFFF | RAM | RAM |

MAME añade wait-states (Takeda pone 24 ciclos en las lecturas de ROM… está
comentado; no lo usa). Empezar sin wait-states.

### 3.1 Puertos I/O del Z80 (decodifica A15..A5, `addr & 0xFFE0`)

| Puerto | R/W | Función |
|---|---|---|
| 0xFF00–0xFF7F | W | `slot_exp[slot_sel] = data & 0x0F` (selección de dispositivo en el slot) |
| 0xFF80 | W | **Máscara de IRQ**: b7 = INT2 → sub (main→sub), b4 = INTS (sub→main), b3 INTD, b2 INTC (RS-232), b1 INTB (FDC IRQ), b0 INTA (FDC DRQ) |
| 0xFFA0 | W | b0 = `slot_sel` (paquete 0/1), b1 = `rom_sel` (1 = RAM en 0x0000–0x8FFF) |
| 0xFFC0 | W | Latch **main→sub** (`comm_data` del sub, leído en sub 0xE800) |
| 0xFF80–0xFFFF | R | Latch **sub→main** (`comm_data` del main; sub escribe en 0xE800) |
| resto (0x0000–0xFEFF) | R/W | Slots de expansión (FDC, RAM pack, ROM pack, FP-1100_SD…) |

### 3.2 Interrupciones del Z80 (modo IM 2 con vector fijo por línea)

Prioridad y vector (SN74LS148): **INTS > INTA > INTB > INTC > INTD**

| Línea | bit máscara | vector |
|---|---|---|
| INTS (sub→main, PC3 del 7801 flanco 0→1) | 0x10 | 0xF0 |
| INTA (slot, FDC DRQ) | 0x01 | 0xF2 |
| INTB (slot, FDC IRQ) | 0x02 | 0xF4 |
| INTC (slot, RS-232) | 0x04 | 0xF6 |
| INTD (slot) | 0x08 | 0xF8 |

Takeda: `INT` activa si `request & mask & ~in_service`; el ack pone
`in_service` y devuelve el vector; **el firmware sale de la ISR con `EI` + `RET`
(no `RETI`)**, así que la limpieza de `in_service` se hace al ver `EI`
(`notify_intr_ei`). MAME simplemente hace `INT = pending & mask` sin
in_service. Para el core: `INT_n = |(pending & mask)`; vector en el ciclo
M1+IORQ; INTS se pone a 1 con el flanco de PC3 y se borra en el ack.
El T80 tiene salida `M1_n`/`IORQ_n`: vector = `0xF0 + 2*prio` en el data bus.

## 4. CPU sub (uPD7801) — mapa de memoria

| Rango | Contenido |
|---|---|
| 0x0000–0x0FFF | ROM interna del 7801 (sub1.rom) — dentro del core `upd7801.sv` |
| 0x1000–0x1FFF | ROM sub2.rom |
| 0x2000–0x5FFF | VRAM **B** (16 KB) |
| 0x6000–0x9FFF | VRAM **R** (16 KB) |
| 0xA000–0xDFFF | VRAM **G** (16 KB) |
| 0xE000 (mirror 0x3FE) | HD46505 registro de dirección (W) / status (R) |
| 0xE001 | HD46505 datos |
| 0xE400 (mirror 0x3FF) | W: fila de teclado / beeper (§5) — R: DIP switches (§8) |
| 0xE800 | R: latch main→sub — W: latch sub→main |
| 0xEC00 | W: borra INTF0 (ack teclado) — MAME; Takeda lo ignora |
| 0xF000 | W: registro de color (§6.3) |
| 0xF000–0xFF7F | chargen (sub3.rom; mapeado desde 0xF400 en MAME, desde 0xF000 en Takeda) |
| 0xFF80–0xFFFF | RAM interna 128 B — dentro de `upd7801.sv` |

**Inversión de datos de VRAM**: en las escrituras a 0x2000–0xDFFF se
almacena `~data`; las lecturas devuelven lo almacenado tal cual, y el
generador de vídeo usa lo almacenado tal cual. (El POST comprueba esto;
sin la inversión arranca en modo FP-1000.)

**WAIT de VRAM**: si el sub accede a VRAM mientras `HSYNC` está activo se
le retiene (`WAITB`) hasta que HSYNC cae. Es contención de bus con el
refresco de vídeo. En FPGA con BRAM dual-port no es necesario para
funcionar, pero conviene reproducirlo para mantener el timing del sub
(la ROM depende del tiempo que tarda el borrado de pantalla, etc.). Se
puede hacer literalmente: `WAITB = ~(vram_cs & hsync)`.

### 4.1 Puertos del 7801

**Puerto A (salida)** `pa`:

| bit | función |
|---|---|
| 0,1,2 | habilita cañones **G, R, B** (orden bit0=G, bit1=R, bit2=B) |
| 3 | 1 = 40 columnas (CRTC clock /16), 0 = 80 columnas (/8) |
| 4 | 1 = pantalla verde (mono, OR de los 3 planos), 0 = RGB |
| 5 | flanco 1→0: **borrar VRAM** (rellena cada plano con 0xFF si el bit de color de fondo correspondiente está a 1, si no 0x00) |
| 6 | CMT baud (1 = 300, 0 = 1200) |
| 7 | CMT clock de carga |

**Puerto B**: entrada = columnas de teclado de la fila seleccionada (solo si
E400 bit5 = 1, si no lee 0); salida = datos Centronics.

**Puerto C** (`pc`):

| bit | dir | función |
|---|---|---|
| 0 | in | Centronics BUSY |
| 1 | in | Centronics ERROR |
| 2 | in | CMT: reloj de carga (**va al pin SCK** del 7801) |
| 3 | out | **INTS al Z80** (flanco 0→1) |
| 4 | out | Centronics dirección |
| 5 | out | relé motor CMT |
| 6 | out | Centronics STROBE |
| 7 | in | CMT: dato serie de carga (**va al pin SI**) |

**SO** (salida serie del 7801) = dato al CMT: selecciona 2400 Hz (1) / 1200 Hz (0).

### 4.2 Interrupciones del 7801

| Línea | origen |
|---|---|
| INT0 (nivel) | bit 7 de la columna de teclado leída (fila de PF0..PF9 / BREAK / STOP): `INTF0 = key_data & 0x80`. MAME lo borra escribiendo 0xEC00 |
| INT1 | no usado |
| INT2 (flanco, polaridad por MK.5) | **main→sub**, ver §7 |
| INTS | fin de byte serie (SIO) — cinta |
| INTT | timer interno |

## 5. Teclado (matriz 16 filas × 8 bits)

`E400` bits 3..0 = fila; bit 4 = beeper; bit 5 = 1 → habilita lectura de
datos (0 → puerto B lee 0). Filas 13/14/15 con bit5=1: LED SHIFT / LED CAPS /
apagar LEDs. **Bit 7 de cada fila dispara INT0.**

| Fila | b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7 |
|---|---|---|---|---|---|---|---|---|
| 1 | SHIFT | CTRL | GRAPH | CAPS | KANA | — | — | **BREAK** |
| 2 | A | ESC | KP- | Q | Z | KP* | ENTER(KP) | **PF0** |
| 3 | S | 1 ! | KP+ | W | X | KP/ | KP, | **PF1** |
| 4 | D | 2 " | KP3 | E | C | DEL | KP. | **PF2** |
| 5 | F | 3 # | KP6 | R | V | → | KP000 | **PF3** |
| 6 | G | 4 $ | KP9 | T | B | INS | SPACE | **PF4** |
| 7 | H | 5 % | KP8 | Y | N | ↓ | KP0 | **PF5** |
| 8 | J | 6 & | KP5 | U | M | ↑ | KP2 | **PF6** |
| 9 | K | 7 ' | KP4 | I | , < | HOME/CLS | KP1 | **PF7** |
| 10 | L | 8 ( | KP7 | O | . > | ← | ] } | **PF8** |
| 11 | ; + | 9 ) | RETURN | P | / ? | BS | [ { | **PF9** |
| 12 | : * | 0 | ^ ~ | @ ` | _ | ¥ \| | - = | **STOP/CONT** |
| 0,13,14,15 | (sin teclas) |

(Fila 0 vacía. Takeda usa este mismo mapa con VK de Windows.)

## 6. Vídeo

### 6.1 CRTC HD46505
- Dot clock 15.9744 MHz; char clock 1.9968 MHz (80 col) o 0.9984 MHz (40 col, cada píxel se duplica).
- 8 px por carácter; `MA`/`RA` del 6845 forman la dirección de VRAM:
  `addr = ((MA << 3) | RA) & 0x3FFF` (por plano). Es decir, cada "carácter"
  del 6845 son 8 bytes consecutivos (8 líneas de raster) — modo gráfico puro,
  el chargen lo usa el firmware del sub por software.
- Screen 0 = 200 líneas (R9 < 8 → 8 rasters/fila); Screen 1 = 400 líneas
  entrelazadas (R9 ≥ 8 → 16 rasters, y en ese modo Takeda replica el plano
  B/R/G por bandas de raster — ver `draw_screen`; MAME lo tiene roto).
- Cursor: color = `color_reg[6:4]` si `color_reg.7`=0, si no 7; parpadeo según R10.

### 6.2 Píxel
Para cada byte: `bit i` (i = 0..7, **bit 0 = píxel izquierdo**) →
`col = B<<0 | R<<1 | G<<2` con `B = pa.2 ? vram_b : 0`, `R = pa.1 ? vram_r : 0`,
`G = pa.0 ? vram_g : 0`. Si `pa.4` (verde): `B=R=G = B|R|G`.
Paleta: índice i → R = (i&2), G = (i&4), B = (i&1) a 255.

### 6.3 Registro de color (sub 0xF000)
b2..b0 = color del borde (B,R,G); b7 = 1 → b6..b4 = color del área de
display (usado por el borrado de VRAM), b7 = 0 → b6..b4 = color del cursor.
Reset = 0x70.

## 7. Handshake main ↔ sub (resuelto en simulación, ver §13)

Latches: el Z80 escribe en 0xFFC0 → el sub lo lee en 0xE800; el sub escribe
en 0xE800 → el Z80 lo lee en IN 0xFF80–0xFFFF. Dos latches independientes,
que conservan el último valor (no se borran al leer).

**INT2 del sub = bit 7 de la máscara (0xFF80), sin más lógica.** Es lo que
hace la ROM del Z80: para cada byte que envía o contesta escribe la máscara
con el bit 7 a 1 y acto seguido a 0 (`90h` → `10h`, o `94h` → `14h`), y el
sub sondea el flag INTF2 con `SKIT`/`SKNIT` (que lo borra). La polaridad del
flanco la elige el sub con MK.5; el core uPD7800 de SCV ya lo implementa así.
No hace falta el flip-flop "latch lleno" ni los parches de Takeda.

**INTS al Z80 = PC3 del sub, de NIVEL.** El sub sube PC3 y no lo baja hasta
recibir el INT2 de respuesta (rutina 0FB9 de la ROM interna: `mov e800h,b;
di; ori pc,08h; skit intf2; jr $-2; ani pc,f7h; mov a,e800h; eqi a,00h;
jr $-7`). Si el Z80 tiene instalada otra ISR cuando llega el byte (ocurre al
empezar un bloque: la ISR 8E2F sólo lee), la vuelve a tomar en cuanto hace
`EI` hasta que instala la ISR 0D33 (lee, escribe 00 en 0xFFC0 y da el
pulso INT2). Con INTS por flanco esa carrera bloqueaba la máquina. En el core
se retiene además el flanco de subida, porque la rutina 0F96 hace un pulso
de sólo 8,5 µs.

Prioridad y vectores confirmados: INTS 0xF0 > INTA 0xF2 > INTB 0xF4 >
INTC 0xF6 > INTD 0xF8; el vector se congela al empezar el ciclo de
reconocimiento (el T80 lo lee varios ciclos después de bajar M1/IORQ).

## 8. DIP switches (sub lee 0xE400)

| bit | 1 | 0 |
|---|---|---|
| 0 | 80 col | 40 col |
| 1 | Screen 1 | Screen 0 |
| 2 | FP-1100 (RGB) | FP-1000 (verde) |
| 3 | 300 baud | 1200 baud |
| 4 | impresora FP-1012PR | — |
| 5 | siempre 1 | — |

Takeda devuelve 0xFC (FP-1100, 1200 bd) / 0xF4 (300 bd). Exponerlos en el OSD.

## 9. Cinta (CMT)

Salida: SO del 7801 selecciona 2400/1200 Hz de un divisor a 76.8 kHz
(4800 Hz × 16). Entrada: circuito discreto (74LS74×4, LS151, LS93, TC4024)
que convierte el audio en **SCK + SI** para el SIO del 7801 en modo reloj
externo; Takeda lo emula puerta a puerta (`update_cmt`). El core uPD7800 de
SCV **no implementa el SIO** (`gen-ucode.py`: "SIO, PEN, PEX, PER, IN, OUT
not implemented"). Hay que añadirle:
- instrucción `SIO` (opcode 0x09): arranca transferencia de 8 bits del registro S.
- pines SI, SO, SCK; modo reloj externo (MC.7) e interno; INTS al completar 8 bits.
- `PER` es NOP también en Takeda — no bloquea.

Plan más práctico para la FPGA: como en otros cores, cargar .bin/.bas
directamente en RAM desde el OSD (los formatos de FP-1100_SD, `SDE8.TXT`/
`SDF8.TXT`, describen las cabeceras), y dejar la cinta real (WAV/CAS por
entrada de audio o reproducción interna) para una fase posterior.

## 10. Esquema (service manual, hoja ①) — `fp1100_main_board_sch1.jpg`

El zip de elektrotanya contiene dos JPG **idénticos** (mismo MD5): sólo la
hoja ① "FP-1100 C.P.U MAIN CIRCUIT", 1600×1129 px. Es la placa del Z80; la
placa sub (uPD7801, CRTC, VRAM, CMT) está en la hoja ②, que no viene. Lo que
sí confirma la hoja ①:

- Lista de ICs: uPD780C-1 (Z80A), 8 × HM4864P-2 (64 K DRAM), HN61256P (ROM
  32 K) + HN462532 (ROM 4 K), SN74LS148 (D14) + SN74LS157 (D13) = codificador
  de prioridad que pone el vector en D1..D3 durante el ack → confirma los
  vectores 0xF0/F2/F4/F6/F8 y la prioridad INTS > INTA > INTB > INTC > INTD.
- Las líneas INTA..INTD y NMI vienen del bus de expansión con pull-ups; se
  enmascaran con NAND (C14/C15) contra el registro de máscara (LS273, C9).
- Latches de comunicación: LS273 (C10) y LS74 (B12/C12) junto al bus de
  datos; con esta resolución no se puede seguir la lógica de INT2. Queda
  la hipótesis de §7, respaldada por la nota de Takeda (§11).
- La resolución es insuficiente para más detalle; si aparece un escaneo mejor
  o la hoja ②, actualizar §7 y §9.

## 11. Página WIP de Takeda (traducción de lo relevante)

`docs/img/` contiene las capturas. Resumen cronológico:

- **2010/6/16** — Volcó la ROM del Z80 y la ROM interna del sub por "captura
  de vídeo": muestra la ROM como patrón en pantalla y la graba con cámara.
  Como el Z80 no puede leer la ROM interna del 7801, envía un programita al
  sub con `DEFCHR$` + `CALL &HB00,&H6B` que copia bytes de la ROM a VRAM y
  los lee con `POINT`. (Explica por qué `sub1.rom` existe y por qué el
  chargen `sub3.rom` es "BAD_DUMP" de 0xF80 bytes.)
- **2010/8/27** — Primer arranque de BASIC (`100827-1.png`, `100827-2.png`).
  Cita clave sobre el handshake: *"Al enviar un comando desde el Z80 al sub,
  se saca el dato y se genera INT2. El sub mira el flag de interrupción para
  salir del bucle de espera de comando y, por alguna razón, espera a que el
  flag se levante otra vez. (Consultar el flag con SKIT/SKNIT lo borra.)
  De momento funciona con trampas, generando interrupciones que no existen
  en el circuito real."* → El sub **sondea INTF2 con SKIT**, no usa la ISR, y
  espera un flanco por byte (comando, luego dato). Encaja con
  `INT2 = mask.7 & latch_full` de §7: cada escritura en 0xFFC0 da un flanco.
  También: VRAM y CRTC están bajo el sub; el borrado de VRAM lo hace un
  circuito externo (→ PA.5).
- **2010/8/31** — Corrige posición de pantalla y colores. Capturas: 80 col
  (`100831-1`), 40 col (`100831-2`), gráficos 320×200 (`100831-3`, texto y
  gráficos comparten pantalla como en el FM-7) y 640×400 monocromo
  (`100831-4`).
- **2015/2/13** — Floppy: arranca CP/M de 56 K (`150213-1.png`).
- **2015/2/21** — Data recorder: emula puerta a puerta el circuito de DFF y
  contadores que detecta flancos, mide la longitud de onda y genera el reloj
  de sincronismo de carga; y rehace el serie del 7801 (SI/SO como señales,
  SCK como reloj externo). Añade máscara de planos de VRAM, corrige el reloj
  del CRTC y añade wait en I/O.
- **2015/3/3** — En SCREEN 1 desactiva la máscara de planos; el borrado de
  VRAM rellena con el valor del registro de color; baudios de CMT en menú
  (correcciones reportadas por un usuario con máquina real).
- **2015/3/12** — uPD765A: SAVE a disco correcto en C86-BASIC.

Pantalla de arranque: `CASIO C82-BASIC Version 1.1 [May 10,1982]` /
`Ready on PROG 0` — es lo que debemos ver en Poseidon.

## 12. Pendientes / preguntas abiertas

1. ~~Hoja ② del esquema~~ → ya está: manual de servicio completo (§14).
2. Presupuesto de BRAM por placa: VRAM 48 KB + ROM sub 12 KB caben en BRAM en
   Calypso (ECP5) sin problema; en SiDi/Poseidon (Cyclone IV) hay que mirar
   cuánto queda tras el framework. RAM principal 64 KB + ROM Z80 36 KB → SDRAM.
3. Modo Screen 1 (400 líneas entrelazadas) — empezar con Screen 0.
4. Slots: RAM pack / ROM pack / FDC (uPD765) — fase 2, con `fdcpack.cpp` de Takeda como referencia.

## 13. Estado del core y simulación (26/09/2026)

`test/` trae un banco de pruebas de la máquina completa para Verilator
(`make sim`, `make teclas`): el Z80 es el tv80 (Verilog) con el bus del
T80pa, la SDRAM es el modelo del core NewBrain, y las ROMs entran por el
mismo camino que data_io. Resultado con las ROMs reales:

- El sub arranca, programa el HD46505 (R0=127, R1=80, R2=96, R3=0x3A, R4=31,
  R5=5, R6=25, R7=28, R9=7, R10=0x27, R11=7 → 80 columnas, 1024 puntos por
  línea, 261 líneas, 59,8 Hz), contesta `7Dh` al Z80.
- El Z80 copia la ROM a RAM (LDIR de 36K, ~190 ms), conmuta a RAM, manda
  `03h` y `2Eh` al sub, recibe el bloque de 248 bytes, y BASIC arranca:
  `CASIO C82-BASIC / Version 1.1 [May 10,1982] / Ready on PROG 0` a los
  ~0,75 s de máquina (`docs/img/sim_print_1+2.png`).
- Teclado PS/2 → matriz: `PRINT 1+2` (con SHIFT para el `+`) y RETURN dan `3`.
- El Z80 pierde un 18 % de sus ciclos esperando a la SDRAM (LDIR incluido).
  Temporización del sub según el core de SCV: `MOV A,word` 17 estados de
  0,5 µs; Takeda usa 20 (su sub es ~35 % más lento, por eso a él no le
  aparecía la carrera de §7).

Pendiente: probar en Poseidon (Quartus), modo verde/FP-1000, SCREEN 1
entrelazado, cinta (SIO en el uPD7800), slots.

## 14. Manual de servicio (Casio FP-1000/FP-1100 Service Manual, ene. 1983)

`docs/img/*_P11xx.png` son los esquemas del manual a 4000 px: placa
principal G205-1 (P1124), placa sub G205-2 hojas 1 y 2 (P1125, P1126) y la
matriz de teclado (P2253). Lo que confirma o corrige respecto a lo anterior:

- **Mapa del sub** igual al de §4; la ROM externa se llama "TEST ROM"
  (1000-1FFF) y el chargen va en F400-FF7F (leído desde F000 da lo mismo).
  0xEC00-0xEFFF W = "acknowledge of INT0".
- **Puertos** (tabla 8-10): PA como en §4.1 (PA5 = 1 borrar VRAM, PA6 = 1
  → 300 baudios, PA7 = 1 → reloj de LOAD). PB = teclado/impresora, PC0 BUSY,
  PC1 ERROR, PC2 reloj de carga del CMT, **PC3 INTS al Z80 ("0" = activo…
  según la tabla; en la ROM `ori pc,08` levanta la petición y así funciona)**,
  PC4 dirección Centronics, PC5 motor, PC6 STROBE, PC7 dato serie del CMT.
  En el esquema SCK (pin 26) está unido a PC2: el SIO trabaja con reloj
  externo, como en Takeda.
- **INTS es de nivel**: PC3 entra por una NAND con la máscara al SN74LS148
  (D14), y su código sale por un SN74LS157 (D13) a D1-D3 del bus. Confirma §7.
- **WAIT del Z80**: las lecturas de la ROM (HN61256P) llevan un registro de
  desplazamiento LS273 (D12) a 0,9984 MHz que mete varios Tw por lectura, y
  cada ciclo de E/S lleva un Tw extra (C17/B17). No está implementado: sólo
  afecta a la velocidad del arranque (el LDIR de la ROM) y del BASIC mientras
  ejecuta desde ROM, que es sólo el arranque.
- **Teclado** (8-12): LS145 decodifica KC0-KC3 (filas), LS174 guarda el
  control (b4 = zumbador, b5 = abre el buffer LS244 de las columnas KI1-KI8).
  El sonido de tecla es el propio firmware pulsando el bit 4 al escanear
  (rutina 023E: `ori c,10h` antes de `mov e400h,c`). **KI8 va a INT0 sin
  pasar por el buffer**, y las filas 13/14/15 con b5 manejan los LEDs
  (1101 SHIFT LOCK, 1110 CAPS, 1111 apagar). Cambiado en `fp1100_sub.v`.
- **VRAM**: 3 × 8 HM4716AP (16K×1) por plano; direcciones = {MA10..MA0,
  RA2..RA0} como en §6.1 (tabla 8-18). El texto dice que **el sub accede a la
  VRAM durante el retrazo horizontal** (8-19) y que el circuito de 8-21 mete
  un Tw por acceso; el multiplexor de direcciones (B12, LS157) conmuta con
  HSYNC y VWAIT sale de B14 (LS74) puesto a cero por VCS. Es decir, en la
  máquina el sub *espera hasta* el HSYNC para entrar en la VRAM, al revés de
  MAME/Takeda (esperan *durante* el HSYNC), y eso haría la escritura en
  pantalla mucho más lenta que en los emuladores. Queda como opción a
  verificar con una máquina real (velocidad de un `CLS` + listado); por ahora
  se mantiene la de Takeda.
- **Modos** (8-17): normal 40/80 × 25 (26 filas en 40 col) = 320×200 /
  640×200; entrelazado 25 filas = 320×400 / 640×400, con caracteres de 8×16.
- **Color** (8-19): b0-2 borde (b0 azul, b1 rojo, b2 verde), b4-6 cursor
  (b7 = 0) o área de display (b7 = 1). Como en §6.3.
- **Cinta** (8-14/8-15): el circuito de muestreo con LS74/LS93/TC4024 está
  en la hoja 2 abajo a la derecha (F17, B16, G21, E14, E19). Para la fase
  de cinta.
- Referencias externas: hilo "Casio FP-1100 and FP-1000" en forum.vcfed.org
  (threads/casio-fp-1100-and-fp-1000.1239013) — no se puede leer sin sesión
  desde aquí; revisar a mano.

## 15. Primera prueba en Poseidon (27/09/2026)

Arranca, hay vídeo (con algo raro pendiente de concretar) y el teclado
funciona, con el sonido de tecla del firmware. Una tecla se quedó pegada:
causas probables y cambios hechos:

- `fp1100_ps2.v` no trataba la secuencia E1 de la tecla Pausa (E1 14 77 /
  E1 F0 14 F0 77): dejaba CTRL (14) pulsado para siempre. Corregido.
- INT0 estaba condicionado al bit 5 del registro de teclado; en la placa no
  lo está. Corregido (afecta a PF0-PF9, BREAK y STOP).
- Falta comprobar en la placa: dos SHIFT a la vez (los dos van al mismo bit)
  y teclas del PC sin equivalente (se ignoran).

## 16. Disquetera: FDC pack con imágenes EDSK (27/09/2026)

`rtl/fp1100_fdc.v` + `rtl/u765/u765.sv` (el uPD765 de los cores de Amstrad/
NewBrain de MiST). Sacado de `fdcpack.cpp` de Takeda y de la IPL de la ROM
(rutinas 0100-05E0):

- El pack es el **dispositivo 0 del slot 1**: OUT FFA0 ← xxxxxx0 (PSL1),
  OUT FF00 ← 0, y el IPL lo reconoce leyendo **04h** en IN FF00-FF7F (la IPL
  lee cinco veces y exige que se repita). Con el pack elegido, cualquier
  IN/OUT por debajo de FF00 va a él y sólo cuentan A2-A0:
  W 0/1 motor, W 2/3 **TC**, R 4 MSR, R/W 5 datos, R/W 6 datos con DACK.
- DRQ → INTA (vector F2, ISR 05CD/05D3: `IN A,(C)` / `OUT (C),A` con C = 6,
  un byte por interrupción, la CPU en HALT entre bytes). INT → INTB (vector
  F4, ISR 0557: sense interrupt / lectura de los 7 bytes de resultado).
- Formato 2D: 40 pistas, 2 caras, 16 sectores de 256 bytes (N = 1), 320K;
  la rutina de formateo de la ROM (03DD) lo confirma (B = 10h sectores,
  CP 28h pistas). Especificación 03 07 1C; lectura 66 C H R 01 EOT=10 1B FF.
- Cambios en u765: INT también al entrar en fase de resultado (hasta leer
  el primer byte), salida DRQ (EXM & RQM) y entrada TC (termina con ST0 = 00
  aunque no se llegue a EOT; sin TC la ROM vería "end of cylinder" y lo
  tomaría por error). Pendiente menor: tras TC el 765 real devuelve R+1 en
  los resultados; el u765 devuelve R.
- Menú: `S0U/S1U,DSK` para montar A: y B:, y `OB` para quitar el pack (sin él
  el IPL no lo ve y arranca BASIC directamente).
- `tools/d88toedsk.py`: D88 (Takeda) ↔ EDSK, y `--nuevo` crea un disco 2D
  vacío formateado. `make disco` simula el arranque con ese disco: el IPL
  encuentra el pack, recalibra, busca pista 0, lee el sector 1 por DRQ, TC,
  INT y resultados, y al no haber sistema vuelve a BASIC.
- Sin probar: escritura (el camino sd_wr está cableado), formateo, unidad B,
  y sobre todo un disco de sistema de verdad (CP/M 56K o C86-BASIC): hacen
  falta imágenes D88 del FP-1100.

## 17. Imágenes de disco reales: CP/M arranca en simulación (27/09/2026)

`tools/disk2edsk.py` convierte IMD (ImageDisk), TD0 (Teledisk, incluida la
compresión "avanzada" LZSS+Huffman) y D88 a EDSK. Los TD0 de la colección
que circula están "pasados por UTF-8" (cada byte ≥ 80h convertido en dos);
la herramienta lo deshace sola. Todas las imágenes son 40 × 2 × 16 × 256,
MFM 250 kbps, entrelazado 2:1 (1, 9, 2, 10, …).

| Imagen | Contenido | Arranca |
|---|---|---|
| fp1000fl.td0 | CP/M 2.2 58K "for FP-1000 Series", sólo disquete | sí |
| fp1000hd.td0 | CP/M 2.2 con disco duro | sí |
| fp10bios.td0 | fuentes del BIOS de CP/M | sí |
| DBASEIIA/B, MBCOMPIL, WSTAR330, XMODEM (IMD) | discos CP/M de sistema | sí |
| GAMDEMO2, ORIGDEMO (IMD) | juegos y demos (arranque propio, `JP 9020` + "BOOT") | sí |
| Cross_Chase (d88) | juego z88dk | sí |
| MBASIC (IMD) | sin sector de arranque (sólo datos) | no |
| JAPGAME1 (IMD) | sector 1 de la pista 0 a ceros | no |
| JAPGAME2 (IMD) | fichero entero a ceros: volcado perdido | no |
| *_td0.___ | no identificados (no son TD0 ni IMD) | — |

El IPL sólo arranca si el sector 1 de la pista 0 empieza por `C3` (JP): lo
carga en 9000h y salta. Con `fp1000fl.dsk` la simulación (`make cpm`) da
`58K CP/M Version 2.2 for FP-1000 Series` en ~3 s de máquina y `DIR` lista
el disco (`docs/img/sim_cpm_dir.png`). El u765 sin `fast` reproduce los
tiempos de giro: 32 µs por byte, ~50 lecturas de sector para arrancar.

## 18. Vídeo: por qué salía roto en Poseidon y el arreglo (27/09/2026)

Las fotos de la primera prueba: en 80 columnas las letras con columnas de
píxeles comidas (`CFSIO CE2-EASIC`), en 40 columnas bien. No era el core:
la línea de la máquina son 1024 puntos de 16 MHz en 64 µs, y doblada son
1024 puntos de 32 MHz a 31,2 kHz / 60 Hz. El monitor no conoce ese modo,
supone 640x480 (800 puntos a 25 MHz) y remuestrea nuestros 1024 con su
reloj: pierde una columna de cada cinco. Con píxeles de dos puntos (40 col)
no se nota. Es exactamente lo que rampa069 encontró y arregló en el
NewBrain (commit "Video: solo puntos de 13,5 MHz").

Arreglo, igual que allí: la salida va a **13,5 MHz, 864 puntos por línea**
(los mismos 64 µs), que doblada es el 720x480 de 27 MHz que los monitores
reconocen y muestrean punto a punto. Como el CRTC tiene que seguir contando
a 16 MHz (de él dependen el WAIT del sub, el cursor y la temporización), el
vídeo se parte en dos:

- `fp1100_video.v`: el HD46505 en clk_sys, solo temporización. Al empezar
  cada línea entrega MA del primer carácter, RA, visible, vsync, R1, PA3,
  cursor…, y un toggle `linea_tgl`.
- `fp1100_display.v`: en clk_pix (27 MHz, c2 del PLL), sincroniza el toggle
  con dos flip-flops, realinea su contador de 864 en cada línea (1024/16 =
  864/13,5, duran lo mismo) y dibuja: 40 puntos de borde, 640 de imagen, 40
  de borde, porche, hsync de 64 y porche. La VRAM tiene el puerto B en
  clk_pix. Da también `hsync_cs` para el compuesto de 15 kHz (pulso al final
  de la línea durante la vsync, como en el NewBrain).

`mist_video` va con clk_27 y `ce_divider = 1`. Los `.sdc` vuelven a tener
los dos grupos de reloj asíncronos. Probado en simulación: BASIC 80 col,
CP/M y la demo de Casio en 40 columnas y color (`docs/img/sim_demo_40col.png`).

Otros dos puntos de la prueba en Poseidon:

- **Con el FDC pack y sin disquete, pantalla en negro**: la IPL recalibra,
  el u765 contestaba `E8h` (ready cambió) al SENSE INTERRUPT y la ROM se
  quedaba esperando el fin de la búsqueda. Ahora contesta `68h` (anormal,
  SE, NR) y la IPL da el arranque por fallido y entra en BASIC, con o sin
  disco.
- `FILES` → `FC error` en C82-BASIC es normal: la BASIC de la ROM no sabe
  de disco; para eso hace falta C86-BASIC (disk BASIC) o CP/M.

## 19. Cinta (27/09/2026)

Tres piezas nuevas, y la ida y vuelta completa probada en simulación:
`SAVE "CAS0:A"` de `10 PRINT "HOLA"`, `NEW`, `LOAD "CAS0:A"` (la ROM contesta
`A . S B P` al encontrar el fichero) y `LIST` devuelve el programa. El SAVE
graba 10,4 s de cinta (46561 flancos: cabecera, parada del motor, cuerpo).

1. **SIO en el core uPD7800** (`rtl/upd7800/upd7800.sv`, según el
   `upd7801.cpp` de Takeda y la hoja de datos del µPD7800): registro S
   (`MOV A,S` / `MOV S,A` = 4C C8 / 4D C8, ya estaban decodificados como
   USPR_S), instrucción `SIO` (09h) añadida a mano en las tablas generadas
   (`uc-types.svh`: UA__19F → UA_SIO; `urom.svh` [415] como NOP;
   `uc-ird.svh` 0x009), pines SI/SCK/SO. Con reloj externo (MC.7 = 1, el
   caso del FP-1100) SO saca el bit 7 de S en el flanco de bajada de SCK y
   SI entra por el bit 0 en el de subida (MSB primero, como dice la hoja de
   datos); cada 8 bits, INTS (flag 4, vector 40h). `SIO` solo pone el
   contador de bits a cero. Con reloj interno se desplaza cada 4 estados.
2. **Circuito de casete** (`rtl/fp1100_cmt.v`): transcripción puerta a
   puerta del modelo de Takeda (`sub.cpp`, `update_cmt`) de la hoja 2 del
   esquema: B16 (sincroniza EAR), F21 (TC4024, mide el periodo del audio
   saturando a 48 × 13 µs = 625 µs: 2400 Hz no llega, 1200 Hz sí), G21
   (dato demodulado), C16 (LS93, cuenta periodos desde el último cambio de
   bit) y C15 (LS151, elige qué hace de SCK según {PA7, PA6, SI}). Reloj
   de 76,8 kHz por acumulador (32 MHz × 3/1250). MIC = SO ? 2400 : 1200 Hz.
   Los detalles están en la cabecera del fichero.
3. **Reproductor de WAV** (`rtl/fp1100_tape.v`): el fichero entra por el
   OSD (`F2,WAV`) a la SDRAM en 010000h (caben 4 MB: ~3 min a 22 kHz y 8
   bits; conviene convertir los WAV a mono 22050 Hz 8 bits). Recorre los
   chunks RIFF (`fmt `, `data`, salta los demás), y mientras el relé del
   motor (PC5) está activo lee una muestra a la frecuencia del fichero
   por el puerto A de la SDRAM; EAR = signo. El motor lo maneja la
   máquina, como con un casete con control remoto.

Menú: `Load tape` (WAV), `Tape input` (WAV / Audio in: la entrada
AUDIO_IN de la placa, ya digital), `Tape` (Play / Pause), `Rewind tape`.
El LED parpadea con la cinta en marcha; por el audio se oye bajito lo que
se graba (MIC) o lo que se carga (EAR), como el altavoz de un casete.

`make cinta` (TECLEAR=3) hace la ida y vuelta con un modelo de casete en
el banco (los flancos de MIC se guardan por tiempo de cinta, que solo
corre con el motor) y además vuelca la grabación a `hola.wav`;
`make cintawav` (TECLEAR=4) carga ese WAV por el reproductor y hace
`LOAD` + `LIST`.

Sin probar en la placa: todo. Y sin hacer: grabar a fichero (SAVE va al
audio de salida; para guardar hay que grabar el audio) y el .bin/.bas
directo por OSD (formatos de FP-1100_SD).

## 20. Vídeo, segunda vuelta: 800 puntos de 12,5 MHz (27/09/2026)

Con los 864 puntos de 13,5 MHz de la §18 la imagen salió peor (letras como
ruido, y el OSD igual). La causa: el FP-1100 es una máquina de 60 Hz (261
líneas, 59,8 Hz). Doblada, el monitor la ve a 31,25 kHz / 60 Hz y la toma
por **640x480 VGA, que son 800 puntos por línea** (el Dell lo dice:
"640x480 @ 60Hz"), y muestrea con su reloj de 800. El truco de rampa069 en
el NewBrain funciona porque aquella máquina es de 50 Hz: allí el monitor
ve 576p, que sí son 864 puntos a 27 MHz. Lo que no se trajo bien fue el
porqué, no el código.

Arreglo: 800 puntos de 12,5 MHz por línea (64 µs, igual que los 1024 de
16 MHz del CRTC), que doblados son el 640x480 de 25 MHz: 640 de imagen, 16
de porche, 96 de sincronismo, 48 de porche, exactamente VGA. `clk_pix`
pasa a 25 MHz (c2 del PLL). En Poseidon es exacto: VCO de 800 MHz, 32 y 25
MHz salen del mismo, y la relación 25/32 es la de 800/1024. Simulado: la
hsync sale con periodo de 1600 ciclos clavados. Sin borde de color (no cabe
en 640 activos); la imagen ocupa todo el ancho, como en los emuladores.

**SiDi y Calypso**: con sus cristales (27 y 12 MHz) un solo PLL no puede dar
32 y 25 MHz exactos a la vez (el VCO tendría que ser múltiplo de 800 MHz).
Sus `pll.v` piden 25 MHz y Quartus dará lo más cercano; si la relación no
sale exacta, el contador de puntos se realinea de vez en cuando y la imagen
salta un punto. Pendiente para cuando se porten: un segundo PLL en cascada,
o bajar el sistema a una frecuencia que case.

**Centrado** (como en el NewBrain): `H centre` 0, +4, +8, +12, −16, −12,
−8, −4 puntos (mueve la imagen dentro de la línea; el sincronismo queda
fijo y siempre con 16 puntos o más de porche) y `V centre` 0, +2, +4, +6,
−8, −6, −4, −2 líneas (retrasa la vsync respecto a las líneas). + es a la
derecha y hacia abajo.

## 21. SiDi: VRAM en SDRAM, relojes y cinta (27/09/2026)

**Memoria.** En el EP4CE22 (66 M9K, 608.256 bits) no cabía: el diseño pedía
656.724 bits, 393.216 de ellos la VRAM. Con la macro `VRAM_SDRAM` (solo en
`sidi/fp1100_sidi.qsf`) la VRAM va a la SDRAM en 600000h, 4 bytes por byte
de VRAM ({v, plano}: B, R, G y uno libre). El video ya no lee la VRAM punto
a punto en ninguna placa: `fp1100_vfetch` lee la línea entera mientras el
CRTC la recorre (80 lecturas de dos palabras con un ACTIVE, puerto V del
controlador, ~43% de la línea) a un buffer de dos bancos, y
`fp1100_display` la dibuja en la siguiente (todo, vsync incluida, sale una
línea más tarde). El 7801 entra por el puerto B con WAIT hasta que la SDRAM
contesta; el borrado por PA5 escribe palabras enteras (~8 ms en vez de 0,5).
Simulado en los dos modos: tramas idénticas a las de antes.

**Imagen.** Se probó a mover la imagen 8 puntos a la derecha (porches 56
y 8), pero en otros monitores salía desplazada: se vuelve al VGA estándar
(48 y 16) y `H centre` a 0, +4, +8, +12, −16…−4. "Video line sync"
compartía `status[14]` con `H centre`: pasa a `OK`. Hay que dejarlo en
*Locked*: en *Free run* (diagnóstico) una línea horizontal pierde un punto
de vez en cuando, porque el contador de puntos no se vuelve a alinear.

**Relojes: lo que quedó pendiente en la §20.** En la SiDi la imagen no
enganchaba en "Locked" y en "Free run" saltaba arriba y abajo. Era la
relación 25/32 inexacta: el PLL pedía 27 × 32/27 y 27 × 25/27, que juntos
necesitan un VCO de 800 MHz con N = 27 (comparador a 1 MHz, fuera de rango),
y Quartus aproximaba. El contador de puntos se apartaba de la línea del CRTC
en cada línea: en "Locked" se realineaba en cada línea (cada línea duraba
distinto, el monitor no engancha); en "Free run" la hsync era estable pero
las líneas del video y las del CRTC se deslizaban y la vsync bailaba.
Arreglo: en SiDi y Calypso, dos PLL con la misma entrada, uno para cada
reloj. Cada uno tiene su VCO y sale exacto, y como los dos siguen al mismo
cristal no derivan entre sí (la fase entre ellos da igual: el vídeo cruza
de dominio por un toggle sincronizado). El sistema sigue a 32 MHz justos.

| placa    | entrada | sistema (c1)             | píxel (c2)                    |
|----------|---------|--------------------------|-------------------------------|
| Poseidon | 50      | un PLL: VCO 800, /25     | el mismo: /32                 |
| SiDi     | 27      | PLL 1: VCO 864 (×32), /27 | PLL 2 (`altpll_vid`): VCO 675 (×25), /27 |
| Calypso  | 12      | PLL 1: VCO 768 (×64), /24 | PLL 2 (`altpll_vid`): VCO 600 (×50), /24 |

Los `.sdc` de las dos placas nombran el reloj de vídeo como
`pll|altpll_vid|auto_generated|pll1|clk[0]`. El `pll.v` de la Calypso ya
no es el del asistente (editado a mano: no regenerarlo).

**Cinta.** Opción `Tape monitor` (Motor on / Always / Off) para oír EAR sin
el motor. `make` con `TECLEAR=5 +WAV=fichero` hace `LOAD "CAS0:"` desde un
WAV cualquiera e informa cada segundo de la posición.

## 22. Formato de cinta y `tools/fp1100tape.py` (28/09/2026)

Sacado del circuito (§19) y comprobado con una cinta real (*Moo Game*, 41
s): **1 = dos ciclos de 2400 Hz, 0 = un ciclo de 1200 Hz** (a 300 baudios,
8 y 4 ciclos). Cada byte: arranque (0), 8 bits de datos **empezando por el
menos significativo**, **paridad par** y **2 de parada** (1): 12 bits. Cada
bloque va precedido por ~3 s de guía (unos). Un programa BASIC son dos
bloques: cabecera `'H'` (48h, 39 bytes, nombre de 8 caracteres en los bytes
2-9) y datos `'D'` (44h). En *Moo Game*: 39 + 2913 bytes, cero errores de
paridad, y tras los datos unos bits que no forman bytes (la ROM los graba
así; se conservan). No había CAS para esta máquina (los `.cas` del Common
Source Project son de MSX, M5 y PC-6001), así que `fp1100tape.py` define
uno, descrito en su cabecera: fragmentos de guía / bytes / bits sueltos /
silencio, sin perder nada de lo que ve la máquina.

`fp1100tape.py ENTRADA [SALIDAS]` lee WAV (cualquier PCM), CAS o TZX y
escribe CAS, TZX (bloques 19h, TZX 1.20: símbolos de 2×1458 T y 4×729 T),
WAV limpio (22050/8 por defecto) o TAP (el de los emuladores de Takeda, que
eFP-1100 carga). Sin salidas, informa de los bloques (`-v`: volcado hex).
Moo Game: WAV de 3,6 MB → CAS de 3 KB. Probado: WAV → CAS/TZX/WAV/TAP → se
vuelve a leer idéntico; y con ruido, nivel bajo, continua, filtro paso bajo
y ±4% de velocidad.

**La polaridad importa**, y no es obvio: la máquina mide el periodo de
flanco de subida a flanco de subida. Con el audio invertido, un 0 seguido
de un 1 da medio ciclo de 1200 + medio de 2400 = 625 µs, justo el umbral de
F21, y la carga falla (probado: 7943 sitios dudosos contra 1). La
herramienta prueba las dos polaridades. En el core la entrada de audio se
invierte siempre: en la SiDi, con una cinta real, solo carga así (hubo una
opción del OSD, `Audio in polarity`, que se quitó al comprobarlo).

## 23. SiDi: texto cian — la SDRAM entrega el dato un ciclo antes (28/09/2026)

En la SiDi el texto blanco salía **cian**, `COLOR 2` (rojo) no se veía y
`COLOR 4` (verde) salía cian; el cursor (que no sale de la VRAM) y el OSD,
bien. Es decir: en el vídeo, el plano azul traía los datos del verde y el
rojo venía a cero. Justo lo que pasa si la lectura doble del puerto V
recoge la **segunda** palabra ({0, G}) en el sitio de la primera ({R, B}).

Causa: en la SiDi el dato de la SDRAM llega **un ciclo antes** de lo que
supone el controlador, y el bus lo mantiene hasta que llega otro (retención
del bus). Las lecturas sueltas funcionan igual (se recogen tarde, pero el
dato sigue en el bus); con los dos READ seguidos del puerto V, la segunda
palabra pisaba a la primera antes de recogerla. La comprobación de planos
del arranque (el sub escribe AAh en 6000h y 55h en A000h y los relee: si
falla, pasa a monocromo y la pantalla queda negra) pasaba, porque va por
lecturas sueltas.

Arreglo: el segundo READ del puerto V sale dos ciclos después del primero,
y cada palabra se recoge tres ciclos después de su READ, igual que una
lectura suelta: funciona con el dato a su hora y con el dato un ciclo
antes. Cuesta dos ciclos por carácter (~11; el vídeo ocupa ~51% de las
líneas visibles).

Banco de pruebas: `+SDRAM_ANTES` hace que el modelo de SDRAM se comporte
como la SiDi (dato un ciclo antes y retenido). Con el controlador anterior
reproduce el cian; con el nuevo, trama idéntica a la de siempre. Además,
`+VRAMLOG` registra los accesos del sub a la VRAM y `+DIP=xx` fija los DIP
(por defecto F5, el de la placa con el OSD de fábrica).

Pendiente: que las lecturas sueltas no dependan de la retención del bus.
Lo limpio sería ajustar en la SiDi la fase del reloj de la SDRAM (o
recoger el dato en el paso 2 solo en esa placa).

## 24. Recoger el dato un paso antes (SiDi, Calypso, MiST) (28/09/2026)

`fp1100_sdram` tiene una entrada `antes`: recoge el dato de cada READ dos
ciclos después de que salga al bus en vez de tres (lecturas sueltas y las
dos palabras del puerto V). Los comandos y los tiempos de la SDRAM no
cambian; solo el momento de recoger, y las lecturas acaban un ciclo antes.

- `SDRAM_ANTES` en el `.qsf` da el valor de la placa: puesto en la SiDi.
  En la Calypso (10CL025, 66 M9K: también lleva `VRAM_SDRAM`) está
  puesto igual que en la SiDi; si allí fallara, comentarlo.
- Se probó con una opción del OSD para cambiarlo sin recompilar: en la
  SiDi funcionaban las dos formas, así que se quitó y se queda la captura
  antes (no depende de la retención del bus, ver tabla). En la Calypso,
  probar compilando con y sin `SDRAM_ANTES`.

Simulación, con el modelo de SDRAM en sus tres comportamientos:

| modelo                                  | captura normal | captura antes |
|-----------------------------------------|----------------|---------------|
| chip ideal (Poseidon)                   | bien           | no arranca    |
| dato un ciclo antes + retención (SiDi)  | bien (§23)     | bien          |
| dato un ciclo antes, sin retención      | no arranca     | bien          |

La tercera fila es la razón del cambio: con la captura normal la SiDi
funciona solo porque el bus retiene el dato; con la captura antes no
depende de eso. Con `antes` el Z80 va un poco más rápido (cada lectura
acaba un ciclo antes). Banco: `+CAPTURA_ANTES`, `+SDRAM_ANTES`,
`+SIN_RETENCION`.

MiST (cuando se porte): EP3C25, también 66 M9K → `VRAM_SDRAM`, y probar
`SDRAM read timing` como en la Calypso.

## 25. Screen 1: pantalla negra y sin OSD (28/09/2026)

El DIP *Screen* (bit 1, OSD `Screen`) elige el modo de pantalla con el que
arranca la máquina: Screen 0 = 640×200 en color; Screen 1 = 640×400
entrelazado (monocromo: rasters 0-7 de cada fila del plano B y 8-15 del R,
como en Takeda). Se lee al arrancar: hay que hacer reset tras cambiarlo.

Con Screen 1 la ROM programa el CRTC en entrelazado con vídeo: R8 = 3,
R9 = 14, R4 = 31, R5 = 5. En ese modo el HD46505 hace filas de **R9 + 2**
rasters (16), 8 por trama: la par 0, 2 … 14 y la impar 1, 3 … 15. El core
contaba hasta R9 y la trama impar se quedaba en 13: 7 rasters por fila,
tramas alternas de 261 y 229 líneas, y el monitor perdía la sincronía
vertical. El OSD se pinta sobre la señal de vídeo del core, así que
desaparecía con ella.

Arreglado en `fp1100_video` (`ultima_raster`): las dos tramas de 261
líneas, igual que Screen 0 (simulado: vsync de 261 líneas fijas; Screen 0,
trama idéntica a la de siempre). Limitación: el scandoubler dobla cada
línea de la trama, así que las dos tramas se pintan en las mismas líneas y
se alternan a 30 Hz (como un monitor entrelazado, con parpadeo en los
detalles finos); para ver las 400 líneas a la vez haría falta combinar las
dos tramas (salida de 31 kHz propia en ese modo).

## 26. Screen 1 a 400 líneas: 31 kHz propios (28/09/2026)

Opción `Screen 1 display` (`status[23]`): *Fields* (lo de la §25: cada
trama por el scandoubler, alternándose) o *400 lines*. Con *400 lines*, en
Screen 1 y con el scandoubler activo (con salida de 15 kHz no se usa):

- `fp1100_display` pasa a **modo31**: el contador de puntos a 25 MHz (el
  `ce_pix` que usa todo el módulo vale 1 siempre) y dos líneas de 800
  puntos por cada línea del CRTC: la raster par y la impar de la fila
  (`media`). Sale 640×400 progresivo a 31,25 kHz y 59,8 Hz (522 líneas por
  cuadro, VGA 640×480 casi exacto), monocromo blanco, como Takeda.
- El scandoubler se salta (`scandoubler_disable` de mist_video) y los
  sincronismos van separados (`no_csync`). El OSD se sigue viendo.
- No hace falta memoria de trama: las dos rasters salen de la VRAM, no del
  barrido del CRTC, así que las dos tramas dan la misma imagen completa.
- `fp1100_vfetch` pide las dos rasters en una sola petición (`par`): en
  SDRAM, el segundo READ del puerto V va a la columna +2 (la palabra {R,B}
  de la raster siguiente) en vez de +1 ({-,G}): mismo coste que siempre.
  En block RAM, dos lecturas seguidas. El plano se elige por la raster
  (B para 0-7, R para 8-15).
- En modo31 la dirección del buffer de línea se pone un punto antes (hay un
  punto por ciclo).

Simulado (Screen 1, *400 lines*): vsync de 522 líneas fijas, 400 líneas
visibles, igual en block RAM y en SDRAM (con el modelo de la SiDi); Screen
0 sigue idéntico. `+VGA400` en el banco de pruebas.

Limitaciones: el cursor ocupa las dos líneas de cada línea del CRTC dentro
de R10-R11; `Scanlines` no se aplica (va sin scandoubler).

## 27. Teclas pegadas: repaso (28/09/2026)

Lo que ya estaba resuelto: el prefijo F0 que se perdía con la interfaz
`key_strobe` de user_io (ahora `fp1100_ps2` recibe el PS/2 serie byte a
byte y guarda E0/F0 entre bytes); Pausa (E1 …) filtrada; los SHIFT
"falsos" (E0 12) de las flechas no tocan el SHIFT; resincronización del
receptor tras 2 ms sin reloj.

Lo que quedaba, y cómo queda:

1. **Tecla pulsada al abrir el OSD.** Con el OSD abierto el firmware no
   manda el teclado al core: si se abría con una tecla pulsada (un SHIFT,
   o la propia combinación de teclas), su "soltar" no llegaba nunca. Ahora
   el top suelta todas las teclas al abrir y al cerrar el OSD
   (`osd_enable` de mist_video → `kbd_soltar`).
2. **Dos teclas del PC en la misma del FP-1100** (SHIFT izquierdo y
   derecho, CTRL izquierdo y derecho). Soltar una con la otra pulsada
   soltaba la tecla del FP-1100. Ahora cada una se guarda aparte y entra su
   OR en la fila 1.

Lo que no se puede cubrir desde el core: bytes que el firmware no llegue a
meter en la FIFO PS/2 de user_io (16 bytes; solo con ráfagas muy largas).
Si una tecla se quedase pegada, abrir y cerrar el OSD la suelta.

## 28. Las tres placas iguales (28/09/2026)

- Hay **un solo top** para todas: `rtl/fp1100_top.sv`, que cada proyecto
  toma por `../files.qip`; lo que cambia entre placas va por macros en su
  `.qsf` (`POSEIDON`, `SIDI`, audio, OSD, VRAM, SDRAM). No hay tops por
  placa; si un OSD sale distinto, el proyecto está tomando otra copia del
  RTL (mirar la fecha de la línea de versión del OSD).
- `VRAM_SDRAM` y `SDRAM_ANTES` activas en Poseidon, SiDi y Calypso: las
  tres funcionan igual. En Poseidon, si el BASIC no arrancase, comentar
  `SDRAM_ANTES`.
- "Video line sync" ya no está en el OSD: fijo en Locked.
- Comprobado: el top pasa el lint con las macros de cada placa; simulación
  con VRAM en SDRAM y captura antes (modelo de la SiDi): arranca, teclado
  (`PRINT 1+2`), vsync fija.

## 29. Teclas pegadas en juegos (VEGCRA) y LED de diagnóstico (29/09/2026)

*Vegetable Crush* (GAMDEMO2, `VEGCRA`, se carga en A800h) lee el teclado a
través del sub: le hace escribir 29h/25h/26h en E400h (fila 9/5/6 con el
bit 5 que habilita PB) y le pide el comando 03 (leer PB); mira el bit 2
de las filas 9 y 5 (4 y 6 del teclado numérico) y el bit 6 de la fila 6
(espacio). Simulado (`+TECLEAR=6 +DSK=GAMDEMO2.dsk +LEELATCH`): con 6 y
espacio pulsados el sub contesta 04 y 40 (la mitad de las veces 00: el
barrido del teclado del propio sub cambia E400h entre la selección y la
lectura; en la máquina real igual), y al soltar, 00 siempre: la nave se
para. En simulación no se pega nada.

El enlace user_io → `fp1100_ps2` probado aparte (transmisor de user_io y
receptor del core): bytes, prefijos y paridad bien. Lo que puede perder
bytes es user_io: descarta el paquete PS/2 entero si su FIFO no tiene sitio.

Para verlo en la placa: OSD `LED` = *Keyboard* (`status[24]`). El LED se
enciende mientras la matriz tiene alguna tecla pulsada, cada byte PS/2
recibido lo invierte ~30 ms y una trama mala (inicio, parada o paridad),
medio segundo. En la Calypso, LED[0] = alguna tecla y LED[1] = bytes recibidos (siempre, sin opción).

## 30. Z80 sin esperas de más: la "tecla pegada" de VEGCRA (29/09/2026)

Causa real de lo de VEGCRA: una carrera de tiempos entre el Z80 y el sub.
El juego pide una fila al sub (comando 03), espera con un bucle fijo
(`LD B,28h / DJNZ`, ~140 µs a 4 MHz sin esperas) y lee la respuesta del
latch. El sub pone el dato ~100 µs después de la petición y lo deja ~105 µs;
luego escribe FFh. Con el Z80 del core la lectura llegaba a ~208 µs y el
FFh a ~205-209: en simulación, 130 de 210 lecturas se llevaban el FFh, que
tiene puestos los bits de 4, 6 y espacio; como la comprobación de la
derecha va después de la de la izquierda, gana la derecha: **derecha y
disparo**. Depende de un par de µs, así que cada placa lo nota distinto.

El Z80 llegaba tarde porque `fp1100.v` lo paraba en cuanto empezaba cada
acceso a la SDRAM (un estado T de más por acceso, ~20% del tiempo parado),
y en la máquina real la RAM no tiene esperas. Ahora (`pasos_mem`):

- MREQ baja en el cen_n de T1; las lecturas solo se paran antes del cen_p
  de T3, cuando el T80 toma el opcode, si la SDRAM no ha contestado (tarda
  ~10 ciclos de los 12 que hay: casi nunca).
- Las escrituras se dan por hechas en cuanto el controlador las tiene
  (las guarda y las hace en orden); solo se para si no se pudo pasar.

Simulación: el Z80 pasa del 20% al 5-6% parado; el arranque da la trama
de siempre y `PRINT 1+2` funciona. El sustituto del T80pa del banco de
pruebas (`t80pa_tv80.v`) baja ahora MREQ/RD en el cen_n de T1, como el
T80pa, para que la cuenta sea la misma; el dato lo toma medio estado antes
que el T80pa (si en la simulación llega a tiempo, en la placa también).

Comprobado con el juego (`+TECLEAR=6 +DSK=GAMDEMO2.dsk +LEELATCH`): de 957
lecturas de teclado, ninguna FFh. Antes de pulsar, todo 00; con 6 y
espacio pulsados, 04 en 22 de 24 y 40 en 24 de 24; al soltar, 00 en todas.
La nave va a la derecha mientras se pulsa, se para al soltar y deja de
disparar. El juego lee ahora a ~188 µs de la petición (antes ~208), antes
de que el sub ponga el FFh.

## 31. 960i tras cada reset (29/09/2026)

Tras un reset o una carga de la ROM el monitor pasaba a veces a "960i".
La vsync de `fp1100_display` cambiaba con `nueva_linea`, que cae a ±2
puntos del final de la hsync según cómo quede alineado el contador de
puntos tras el reset (la tolerancia de realineado). Si caía justo en el
borde, el scandoubler veía la vsync unas tramas en una línea y otras en la
siguiente: tramas alternas desplazadas media línea, que el monitor toma por
entrelazado. Ahora la vsync (y la de la señal compuesta) solo cambia al
empezar la hsync (`hcnt == H_SYNC0`), como en VGA: siempre en la misma
posición. Simulado: trama idéntica, vsync de 261 líneas fijas.

## 32. Teclas pegadas: repaso del firmware y red de seguridad (30/09/2026)

Repaso del firmware de MiST (`user_io.c`, el mismo en SiDi y Poseidon):
compara cada informe USB (estado completo de hasta 6 teclas) con su lista
y manda un *make*/*break* por cada cambio, cada tecla en un paquete SPI
(E0, F0, código); un informe perdido no pierde liberaciones (el siguiente
las corrige); no repite teclas por defecto; solo descarta informes "todo
soltado" de un mando de menor prioridad que el teclado. Solo procesa
teclados en modo *boot* (los NKRO puros no valen). En user_io, un paquete
se descarta entero si la cola PS/2 (16 bytes) tiene menos de 4 libres; con
PS2DIV = 100 (158 kHz) se vacía a 76 µs por byte, así que hacen falta 13
bytes en cola: en el MSX1 de la SiDi pasaba con una cola de 8 y un reloj
PS/2 lento (RW-FPGA-devel-Team/MSX1FPGA_SiDi, commit 1919f80: 8 → 16).
No he encontrado ningún core con la cola a 32; `user_io.v` de nuestra copia
de mist-modules tiene ahora el parámetro `PS2_KBD_FIFO_BITS` (4 por
defecto) y el top pone 5: 32 bytes.

Red de seguridad, independiente de dónde se pierda el *break*: el core pide
`FEAT_PS2REP` (1000h) en `FEATURES`, con lo que el firmware (desde 2022)
repite la tecla pulsada unas 15 veces por segundo; repite **una**, la de la
última posición de su lista. `fp1100_kbd` toma por "repitiéndose" la tecla
que recibe un *make* estando ya pulsada, y si pasa 500 ms sin repetirse la
suelta sola. Las teclas que no se repiten no se tocan, y con un firmware
sin repetición nada cambia. Probado aparte (`/tmp/kt`, iverilog): la tecla
repetida se suelta a los 500 ms de dejar de repetirse, la que no se repite
se mantiene, y `PRINT 1+2` sigue funcionando. Con el LED en *Keyboard* se
ve si el firmware repite: parpadea seguido mientras se mantiene una tecla.

## 33. Centrado vertical a 31 kHz (30/09/2026)

A 31 kHz (scandoubler o Screen 1 a 400 líneas) el OSSC se comía la fila de
arriba: nuestras 400 líneas empiezan a 56 líneas de salida del principio de
la vsync y el OSSC coloca su ventana de 480p a su manera. Probado en la
placa: `V centre` +4 lo arregla. El top suma ahora +4 (líneas de la
máquina) a `V centre` cuando el scandoubler está activo; a 15 kHz no
cambia nada. El menú sigue sumando encima; por arriba se queda en +8 (la
vsync no puede adelantarse más: `vs_idx` 0).

## 34. Último punto de la derecha, H a 31 kHz y Screen 1 por defecto (01/10/2026)

- **El punto x = 639 no se veía.** Cada punto sale de `fp1100_display` dos
  ce después de su `hcnt` (registro de desplazamiento y registro de
  salida), pero la `hblank` iba con un solo ce de retraso: la ventana de
  imagen empezaba un punto antes que la imagen y el último punto caía en la
  zona borrada (la carta de ajuste necesitaba grosor 2 para ver la línea de
  la derecha). Ahora `hblank` sale de `en_img` retrasado otro ce. Simulado:
  las líneas de x = 0 y x = 639 se ven.
- **H a 31 kHz:** como la V (§33), el top suma +8 puntos a `H centre`
  cuando el scandoubler está activo (probado en la placa); tope +12.
- **Screen 1 display:** por defecto *400 lines* (`status[23]` = 0).
- `tools/ajuste`: la carta de ajuste (AJUSTE.BAS) y `hazdsk.py`, que la mete
  en un disco que arranca solo, hecho a partir de la estructura de GAMDEMO2
  (programa en texto, tipo 30h, y la orden de arranque `LOAD"0:AJUSTE",R`
  en el sector 1 de la pista 0).

## 35. Teclas pegadas tras una pulsación corta (la I) (02/10/2026)

La matriz de la I está bien (fila 9 bit 3, igual que en Takeda). Lo que
pasaba: la red de seguridad de la §32 solo vigilaba una tecla cuando ya se
había repetido, y el firmware no empieza a repetir hasta ~250 ms. Con
pulsaciones cortas (escribiendo), si se perdía el "soltar", la tecla nunca
llegaba a vigilarse y se quedaba pegada con el LED fijo.

Ahora se vigila la última tecla pulsada desde su primer *make*: si pasan
600 ms sin pulsación ni repetición, se suelta. Solo cuando el firmware ya ha
demostrado que repite (`fw_repite`, al ver la primera repetición); con un
firmware sin repetición, nada cambia. No se vigilan las que el firmware no
repite: CTRL, SHIFT, ALT, ALT GR y WIN (modificadores USB) y Bloq Mayús
(el firmware la enclava: make y break en pulsaciones alternas). Con dos
teclas pulsadas, la anterior no se toca (el firmware repite la última).
Probado aparte: pulsación corta con el soltar perdido → suelta a los 600
ms; mantenida con repetición → no se suelta; KP6 mantenida mientras se
repite el espacio → no se suelta; ALT mantenido 1,5 s → no se suelta.

Nota del firmware: Bloq Num y Bloq Despl no llegan al core (cambian los
modos de emulación de ratón/joystick), así que STOP/CONT en Bloq Num no
funciona con el firmware de MiST.

## 36. STOP/CONT en la tecla Pausa (02/10/2026)

Bloq Num no llega al core con el firmware de MiST (§35), así que STOP/CONT
pasa a Pausa. El firmware manda Pausa como `E1 14 77 E1 F0 14 F0 77` de
golpe al pulsarla y nada al soltarla. `fp1100_ps2` sigue ignorando lo que va
tras cada E1 (si no, el 14 dejaría CTRL pulsado), pero al cerrar el primer
grupo (el que no lleva F0) da una pulsación de 77h, que `fp1100_kbd` ya
tenía en STOP/CONT (fila 12, bit 7), y la suelta sola a los ~131 ms (2^22
ciclos a 32 MHz), tiempo de sobra para el barrido del teclado del sub. Si se
mantiene, el firmware repite la Pausa y llegan más pulsaciones. Probado
aparte con el transmisor de user_io: pulsa 77h, la suelta a los 131 ms, y un
CTRL normal después se pulsa y se suelta bien.

## 37. Macro `Z80_ESPERA_CLASICA` (02/10/2026)

Para aislar fallos de memoria: con `Z80_ESPERA_CLASICA` el Z80 vuelve a la
parada de antes de la §30 (desde el principio de cada ciclo, escrituras sin
adelantar). Revisado otra vez contra `T80pa.vhd`/`T80.vhd`: el opcode se
toma (`IR <= DInst`) en el CEN que cierra T2 y el dato de lectura se
registra (`DI_Reg`) en el CEN_n de T3; la parada nueva bloquea justo el
CEN que cierra T2 si la SDRAM no ha contestado. Las escrituras se adelantan
al controlador, que las hace en orden; una lectura posterior espera a que
el controlador quede libre. El otro sospechoso de fallos de memoria en una
placa concreta es `SDRAM_ANTES` (§23-24): probar a comentarlo.

## 38. Vigilancia global del teclado y prefijos (02/10/2026)

Revisadas dos propuestas externas (Qwen y DeepSeek):

- **Prefijos colgados** (bien visto): si se perdía una trama tras un E0/F0,
  el prefijo se quedaba para la siguiente tecla. Ahora el reinicio de ~2 ms
  sin reloj de `fp1100_ps2` borra también E0 y F0 (el firmware manda prefijo
  y código seguidos, a ~76 µs).
- **Vigilancia global** (idea buena; su versión soltaba también Bloq Mayús,
  que el firmware deja enclavada): `fp1100_kbd` suelta todo si, con el
  firmware repitiendo, pasan 1,5 s sin ningún evento PS/2 y la matriz sigue
  con algo pulsado. Con una tecla mantenida de verdad llegan repeticiones
  cada ~68 ms, así que eso solo pasa con un "soltar" perdido de una tecla
  que la vigilancia de la §35 no cubría: un modificador (SHIFT, CTRL, ALT)
  o una tecla pulsada antes que otra. Bloq Mayús se respeta. Único caso
  malo: mantener solo un modificador más de 1,5 s sin tocar nada más.
  Probado aparte: SHIFT con el soltar perdido se suelta a los 1,5 s; A
  pegada mientras se repite B se suelta 1,5 s después de soltar B; Bloq
  Mayús se mantiene; I mantenida 3 s con repetición no se suelta.
- **Filtro antirrebote en `ps2_clk`/`ps2_data`**: no aplica. No hay cable
  ni teclado PS/2: esas señales salen de `user_io`, en el mismo dominio de
  reloj (`clk_sys`), y se muestrean en flancos; un pico combinacional entre
  flancos no se ve. La prueba de estrés de la §32 no dio ni un error.

## 39. Posición horizontal por modo (02/10/2026)

Probado en la placa con el core de la §34: a 15 kHz la imagen quedaba bien
con `H centre` −16 y a 31 kHz con −8. En puntos de porche trasero (dónde
empieza la imagen tras la hsync), eso era 48 − 16 = **32** a 15 kHz y
48 + 8 − 8 = **48** a 31 kHz. Ahora son los valores por defecto (con
`H centre` a 0): el top da `h_off` −16 a 15 kHz y 0 a 31 kHz (desaparece
el +8 de la §34). El menú suma encima: 16..44 puntos a 15 kHz y 32..60 a
31 kHz; por la derecha la imagen acaba como mucho a 2 puntos de la hsync.

## 40. PS2DIV 1000 (macro `PS2_16KHZ`) (02/10/2026)

Con `PS2_16KHZ` (puesta en los tres `.qsf`) `user_io` saca el PS/2 hacia
el core a ~16 kHz (PS2DIV 1000, como el C64 de MiST) en vez de ~158 kHz.
Probado aparte con el transmisor de `user_io` a esa velocidad: teclas,
prefijos y Pausa bien. Pero ojo: el firmware no espera a que salgan los
bytes, así que a 16 kHz la cola de 32 se vacía diez veces más despacio
(~0,75 ms por byte). En la prueba de estrés con ráfagas artificiales (un
evento cada ~1 ms) se descartaron 41 de 200 paquetes, cosa que a ~158 kHz
no pasaba. Tecleando de verdad (unas pocas decenas de bytes por segundo,
como mucho 18 de golpe) no se llena. Si con la macro se pegan más teclas,
quitarla.

## 41. Sincronismos estándar a 15 y 31 kHz; VGA de 525 líneas (03/10/2026)

Un usuario con OSSC y capturadora veía la imagen de 31 kHz recortada por
abajo (la capturadora decía "522p") y la de 15 kHz algo escorada a la
derecha. Banco nuevo para medirlo sin ROM: `make sd` (`test/tb_sd.sv` +
`test/analiza_sd.py`): CRTC programado como la ROM del sub (R3 = 3Ah: vsync
de 3 líneas), VRAM con una carta de ajuste que lleva el número de cada línea
codificado, y la salida de `mist_video` volcada por ciclo. El analizador da
líneas por cuadro, duración de hsync y vsync, dónde cae la imagen respecto a
ellas (en µs y líneas, comparado con TV y VGA), si salen todas las líneas de
la máquina y las columnas x = 0 y 639, y dos PNG (zona activa y cuadro
entero con sincronismos). `+SD_OFF` 15 kHz, `+SCANDOUBLER` el 31 kHz de
antes, `+SCREEN1` Screen 1 a 400 líneas, `+HOFF`/`+VOFF`. En `tb_fp1100`,
`+VGAHEX` vuelca igual la máquina entera.

**15 kHz** (todas las placas): hsync de 59 puntos (4,72 µs, la de TV; antes
96, la de VGA) y la imagen 4 puntos más a la izquierda por defecto (`h_off`
−20): empieza a 10,0 µs del flanco de la hsync y su centro cae a 35,6 µs,
el de la TV. El OSSC la ve como 261p, 15,62 kHz, 59,86 Hz.

**31 kHz con el scandoubler** (ya no lo usa ninguna placa, ver abajo): la vsync pasa a
ser de 2 líneas (una de la máquina), con la imagen centrada en las 480 de
VGA (40 líneas encima y debajo); antes era la del CRTC doblada (6 líneas).
`V centre` ya no suma +4 a 31 kHz. Pero el scandoubler solo puede dar
261 × 2 = **522 líneas**, no las 525 de VGA: el OSSC la ve como 522p y
algunas capturadoras la recortan. 261 líneas es la máquina (cristal de
15,9744 MHz, R0 = 127, R4 = 31, R5 = 5, R9 = 7 que programa la ROM del sub;
igual en Takeda y MAME): no es un error de reloj del core.

**31 kHz propio, macro `VGA_525`** (las tres placas): `fp1100_vga` genera un
640x480 estándar, 800 × 525 puntos a **25,14368 MHz**: 31,43 kHz y 59,866
Hz, dentro de la tolerancia de VESA (25,175 MHz ±0,5 %). El reloj está
elegido para que 525 líneas de 800 duren exactamente un cuadro de la
máquina (25,14368 = 16 × 420000/267264), así que el cuadro de VGA va
enganchado al del CRTC: se alinea con el principio de la trama una vez y no
se mueve (simulado: la trama del CRTC llega siempre en la línea 68, punto
799). Las líneas no salen del barrido del CRTC: `fp1100_vfetch` escribe
cada línea además en un anillo de 8 (`lb31`, leído con el reloj de VGA) y
la línea de salida k de la imagen pinta la k/2 de la máquina; como 525
líneas de salida duran lo que 261 de la máquina, la salida se adelanta
1,15 líneas en toda la imagen, por eso empieza 6 líneas de salida después
de la trama del CRTC. Screen 1 a 400 líneas sale igual (cada línea del
anillo trae la raster par y la impar), sustituyendo al `modo31` de §26 en
esta placa. Las scanlines las pone ahora `fp1100_vga` (la segunda línea de
cada par). En el top hay dos `mist_video`, los dos sin scandoubler: el de
15 kHz con `clk_pix` y el de 31 kHz con `clk_vga`, cada uno con su OSD, y
a los pines va el del modo elegido.

Reloj en Poseidon (`poseidon/pll_vga.v`): 175/348 de 50 MHz no sale de un
PLL (haría falta N = 12, comparador a 4,2 MHz). Con 175/192 desde un
intermedio Quartus **aproximó** (M = 31, C = 34: 25,16 MHz, y el vídeo se
habría realineado en cada cuadro): hay que mirar siempre la tabla "PLL
Usage" del fitter. Quedan dos PLL en cascada con M pequeños: 50 × 25/12 =
104,1667 MHz y × 7/29 = 25,14368 MHz. Los 50 MHz salen de c3 del PLL
principal (800/16): tomarlos del pin daba el Critical Warning 176598.
Simulado en `make sd`: 525 × 800 en todos los cuadros, vsync de 2 líneas,
480 activas desde la 35, la imagen en la 75-474, las 200 líneas dobladas
(400 rasters en Screen 1, en orden) y x = 0 y 639; `V centre` −8..+6 y
`H centre` −16..+12 bien. Síntesis: sin Critical Warnings, tiempos bien.
Probado en la placa (Poseidon): bien.

**SiDi y Calypso** (mismo RTL, solo cambian los PLL). Respecto al cristal la
relación es 4375/4698 (27 MHz) y 4375/2088 (12 MHz): sin el factor 5 de los
50 MHz, el producto de las M de la cascada tiene que ser múltiplo de 4375 y
una sale de 125. Las dos van por un intermedio de 41,667 MHz:

| Placa | Entrada (c3 de `pll`) | `pll_vga` a | `pll_vga` b |
|---|---|---|---|
| SiDi | 27 MHz (copia del cristal) | × 125/81: M 125, N 3, VCO 1125 | × 35/58: M 35, N 2, VCO 729 |
| Calypso | 24 MHz (cristal × 2) | × 125/72: M 125, N 3, VCO 1000 | igual |

Quartus dio en las dos la relación pedida (columnas Mult/Div de "PLL
Usage"; la frecuencia la redondea a "25.15 MHz" porque parte de 41,67).
Con `pll_vga` las dos placas usan los 4 PLL que tienen.

De paso, fuera los Critical Warnings que ya tenían:
- SiDi: `altpll_vid` (25 MHz) tomaba el cristal del pin, que es el del PLL
  principal (176598). Ahora lo toma de c3.
- Calypso: lo mismo, y además los 12 MHz del cristal quedaban en el borde
  del rango de enganche de `altpll_vid` (15556, "12,0 a 26,01 MHz"). c3 da
  ahora 24 MHz (VCO 480 / 20) y de ahí salen `altpll_vid` (× 25/24, VCO
  600) y `pll_vga`.
- Calypso: `SDRAM_A[12]` sin pin (169085): Quartus lo sacaba por un pin
  cualquiera. **La SDRAM de la Calypso tiene un bit de dirección menos**
  (A0-A11); el controlador nunca pone A12 a 1 (filas de 12 bits), así que el
  top la declara de 12 bits en esa placa (`SDRAM_SIN_A12`).

Síntesis (Quartus 21.1): las tres sin Critical Warnings y con tiempos bien.
SiDi 66 % de la lógica, Calypso 55 %, 42 % de la memoria las dos (sin el
búfer de línea del scandoubler, menos que antes).
