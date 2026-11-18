# Casio FP-1100 / FP-1000 para placas FPGA de la familia MiST

*[Read in English](README.md)*

Implementación en FPGA del **Casio FP-1100** (1982) y de su hermano
monocromo, el **FP-1000**, para las placas **Poseidon**, **SiDi** y
**Calypso**. Ejecuta las ROMs originales en los dos procesadores de la
máquina y arranca el C82-BASIC y CP/M desde imágenes de disco EDSK.

## Características

- **CPU principal**: Z80 a 4 MHz (T80) con un reloj de sistema de 32 MHz; la
  ROM del BASIC y los 64K de RAM van en la SDRAM, y la CPU solo se para
  cuando de verdad necesita un dato que la SDRAM aún no ha entregado.
- **CPU secundaria**: el NEC uPD7801 que lleva el teclado, el vídeo, la
  cinta y la impresora, emulado con un core uPD7800 y la ROM interna
  original, hablando con el Z80 por los mismos latches e interrupciones.
- **Vídeo**: CRTC HD46505 y la VRAM de color de tres planos (48K, en la
  SDRAM), leída con una línea de adelanto a un buffer de línea. 80 y 40
  columnas, 640x200 en ocho colores, el modo de monitor verde del FP-1000 y
  la **Screen 1** (640x400 entrelazada): como tramas alternas o, por
  defecto, como imagen progresiva de 640x400 con salida de 31 kHz propia.
- **Teclado**: PS/2 a la matriz del FP-1100, con protección contra teclas
  que se quedan pulsadas cuando el firmware pierde una liberación.
- **Cinta**: ficheros WAV desde el OSD o audio real por la entrada de audio,
  con monitor de cinta para oír lo que se carga.
- **Disco**: el FDC pack (uPD765) con imágenes EDSK en las unidades A y B;
  CP/M arranca desde disco.
- **Herramientas**: conversor de cintas WAV/CAS/TZX/TAP, conversores de
  imágenes de disco (D88, Teledisk, ImageDisk y volcados a EDSK), un
  desensamblador de uPD7801 y una carta de ajuste en un disco que arranca
  solo.

**ROM**: copia `sd/FP1100.ROM` (48K) a la raíz de la SD; el firmware de la
placa la carga al arrancar el core. En `roms/README.md` está cómo se forma a
partir del set de MAME `fp1100`.

## Cómo funciona

**Dos procesadores, como la máquina real.** El FP-1100 reparte el trabajo
entre un Z80, que ejecuta el BASIC, y un uPD7801 que gobierna el teclado, la
memoria de vídeo, el circuito de cinta y el puerto de impresora. El core
mantiene ese reparto: el T80 ejecuta la ROM del BASIC desde la SDRAM y el
core uPD7800 ejecuta la ROM interna de la CPU secundaria desde block RAM. Se
comunican por los latches y las interrupciones originales, y cada orden del
BASIC que dibuja en pantalla o lee el teclado pasa por el firmware de la CPU
secundaria.

**Memoria.** ROM, RAM y VRAM de color comparten una SDRAM. Un árbitro de
prioridad fija atiende el refresco, el vídeo, la cinta y las CPUs. El vídeo
lee dos palabras por carácter con un solo ACTIVE; el Z80 solo se retiene en
el punto exacto en que tomaría el dato del bus.

**Vídeo.** En vez de leer la VRAM al ritmo de los puntos, el core lee cada
línea del CRTC a un buffer durante la línea anterior, lo que permite tener
la VRAM en la SDRAM en placas con poca block RAM. El reloj de punto es
exactamente 25/32 del reloj del sistema, así que cada línea son 800 puntos
de 12,5 MHz (64 µs) y la salida del scandoubler tiene la temporización
estándar de VGA 640x480.

**Cinta.** El demodulador FSK reproduce el circuito de la propia máquina, y
un reproductor saca los WAV cargados desde el OSD como si vinieran de un
casete con el motor controlado por el ordenador.

**Pruebas.** La máquina entera funciona en un banco de pruebas con Verilator
y las ROMs reales: arranque del BASIC, tecleo, carga de cintas y discos,
CP/M y los juegos usados para cazar problemas de tiempos. Las notas de
desarrollo están en `docs/hardware_fp1100.md`.

## Compilación

Abre el proyecto de tu placa en Quartus (`poseidon/`, `sidi/` o `calypso/`)
y compila. Los bancos de pruebas se lanzan con `make` en `test/`.

`common/` lleva copias de T80 y mist-modules con dos cambios locales
pequeños (un arreglo de arranque en frío en `T80pa.vhd` y la cola PS/2
configurable en `user_io.v`), por eso van como carpetas normales y no como
submódulos.

## Créditos

Este core se apoya en el trabajo de mucha gente. Gracias a todos.

**Código usado en el core**

- **T80**, core Z80: Daniel Wallner, con arreglos posteriores de Sorgelig y
  la comunidad MiST/MiSTer. Licencia tipo BSD.
- **uPD7800**, core: David Hunter, del core de Super Cassette Vision.
  Licencia GPL.
- **Módulos de MiST** (`user_io`, `data_io`, `mist_video`, OSD, scandoubler
  y relacionados): Till Harbaum, Gyorgy Szombathelyi (gyurco) y la comunidad
  MiST. GPL v3 o posterior.
- **u765**, controlador de disquete uPD765: Gyorgy Szombathelyi (gyurco),
  de Amstrad_MiST. GPL v2 o posterior.
- DAC delta-sigma: basado en la nota de aplicación XAPP154 de Xilinx.
- **tv80** (solo en el banco de pruebas): Guy Hutchison. Licencia tipo MIT.

**Referencias e inspiración**

- **eFP-1100** de Takeda Toshiya (Common Source Code Project): la referencia
  principal del hardware; el desensamblador de uPD7801 de `tools/` es suyo.
- El driver FP-1100 de **MAME** (Angelo Salese y el equipo de MAME, BSD de 3
  cláusulas).
- **FP-1100_SD**, por los formatos de fichero y el cargador de arranque.
- El manual de servicio del Casio FP-1000/FP-1100 y el manual del C82-BASIC.
- El core NewBrain del mismo autor, cuya estructura sigue este core.

## Agradecimientos

Al **Retro-Wiki FPGA-dev Team**, en especial a **Ron, Manuel (teiram),
Somhi, Roderick, Rampa, Kyp y Benito**, por su ayuda y su paciencia.

## Asistencia de IA y recursos

Partes de este core se desarrollaron con la ayuda de Claude (Anthropic),
usado para código, bancos de pruebas, simulación y documentación. El acceso a
Claude lo proporcionó Advanced Computer Trading, S.L. (actsl.com), que además
autoriza la publicación de este trabajo bajo la licencia indicada abajo.
Todas las decisiones de diseño, la integración, las pruebas en hardware real
y la revisión final las hizo el autor, Shaeon (Carlos Palmero).

## Licencia

Copyright (C) 2026 Shaeon (Carlos Palmero).

Este programa es software libre: puedes redistribuirlo y/o modificarlo bajo
los términos de la **Licencia Pública General GNU** publicada por la Free
Software Foundation, en su **versión 3** o (a tu elección) cualquier versión
posterior. Ver [LICENSE](LICENSE).

Hace falta la versión 3 porque algunos de los módulos incluidos (los módulos
de MiST) tienen licencia GPL v3 o posterior. Los ficheros de terceros
conservan sus propios avisos de copyright y licencias.

## Aviso

Este proyecto se ofrece **"tal cual", sin garantía de ningún tipo**, expresa
o implícita, incluidas, entre otras, las garantías de comerciabilidad y de
idoneidad para un fin concreto. En ningún caso los autores o colaboradores
serán responsables de ninguna reclamación, daño u otra responsabilidad
derivada del uso de este software, del hardware en el que funciona o de
cualquier equipo conectado. Úsalo bajo tu propia responsabilidad.

Casio, FP-1000 y FP-1100 son marcas de sus respectivos propietarios. Este
proyecto no está afiliado a ellos ni cuenta con su respaldo.
