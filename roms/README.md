# ROMs del FP-1100

Esta en `sd/FP1100.ROM`: hay que copiarla a la raiz de la SD. Es un fichero
de 49152 bytes (48K) que es la concatenacion, en este orden, del set de MAME
`fp1100`:

| Offset | Tamaño | Fichero    | SHA1 (MAME)                              | Destino en el core          |
|-------:|-------:|------------|------------------------------------------|-----------------------------|
| 0x0000 | 36864  | basic.rom  | 985757b9c62abd17b0bd77db751d7782f2710ec3 | ROM del Z80 (SDRAM 000000)  |
| 0x9000 |  4096  | sub1.rom   | 917d5b398b9e7b9a6bfa5e2f88c5b99923c3c2a3 | ROM interna del uPD7801     |
| 0xA000 |  4096  | sub2.rom   | 0188d5a7b859075cb156ee55318611bd004128d7 | ROM del sub en 1000-1FFF    |
| 0xB000 |  3968  | sub3.rom   | a9ae6b03e06ea2f5db30dfd51ebf5aede01d9672 | generador de caracteres     |
| 0xBF80 |   128  | ceros      |                                          | (relleno hasta 48K)         |

Para volver a generarla desde el set de MAME:

    cat basic.rom sub1.rom sub2.rom sub3.rom > FP1100.ROM
    head -c 128 /dev/zero >> FP1100.ROM

El firmware de la placa la carga sola al arrancar el core (entrada `F0` del
menu); tambien se puede volver a cargar desde el OSD.
