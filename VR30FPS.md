# Virtua Racing Deluxe 32X a 30 FPS

Parche que hace que Virtua Racing Deluxe (32X) dibuje a **30 imágenes por segundo** en carrera y en la demo, frente a los ~20 del original. La jugabilidad no cambia: la física, la IA y las colisiones siguen funcionando exactamente igual, a 20 pasos de lógica por segundo.

Todo el código está en este repositorio y se construye con un solo script. La ROM resultante es idéntica byte a byte a la versión probada (v7).

---

## 1. Construir la ROM

Requisitos:

- La cadena de herramientas normal del repositorio: `tools/vasmm68k_mot` y `python3`.
- Binutils de GNU para SH (`sh-elf-as`, `sh-elf-ld`, `sh-elf-objcopy`, `sh-elf-nm`), que el `Makefile` ya necesita para el código SH2.

```bash
# con sh-elf-* en el PATH
./experiments/fps30/build_vr30.sh

# o indicando dónde están
SH_PREFIX=/opt/sh-elf/bin/sh-elf- ./experiments/fps30/build_vr30.sh
```

El resultado es `build/vr30fps.32x`, que funciona en PicoDrive y ya incluye el relleno que necesita Ares.

La ROM de referencia (v7) tiene este SHA-256:

```
e4adbe8b063c4e6d18b0c2ad0cd49b706ae43a2485d367be86fbdbecd81bd024
```

### Qué hace el script

1. **Ensambla el juego** con el planificador de 30 FPS y todas sus opciones activadas (sección 5).
2. **Ensambla las rutinas SH2 nuevas** de `experiments/fps30/sh2/`.
3. **Las inserta en la ROM** con `make_band_rom.py` y aplica `pwpatch.py`. Cada parche comprueba antes los bytes que va a sustituir, así que si la base no es la esperada el script falla en lugar de generar una ROM rota.

---

## 2. La idea general

En el original, la lógica del juego se actualiza 20 veces por segundo y cada actualización se dibuja una vez. En una tele de 60 Hz, cada imagen dispone de **3 refrescos (50 ms)**.

Para llegar a 30 FPS hubo que resolver dos problemas:

1. **Dibujar cada imagen en 2 refrescos (33 ms)**, es decir, en un tercio menos de tiempo. Se consigue repartiendo mejor el trabajo entre los dos SH2 y eliminando esperas (sección 3).
2. **Mostrar 30 imágenes distintas con solo 20 estados de juego por segundo.** Se resuelve con interpolación (sección 4).

---

## 3. Dibujar más rápido (SH2)

### Cómo dibuja el original

Cada imagen pasa por tres procesadores en cadena:

1. El **68000** envía el "bloque de escena" (cámara, coches, objetos) a la 32X.
2. El **SH2 maestro** transforma los vértices a coordenadas de pantalla y va publicando los polígonos, ya ordenados de atrás hacia delante, en una cola circular en SDRAM (`$06018000`, 256 entradas de 64 bytes).
3. El **SH2 esclavo** rasteriza esos polígonos en el framebuffer. Los tramos de color sólido los pinta con el circuito de relleno del VDP de la 32X.

En carrera, el esclavo está ocupado en torno al 80 % del tiempo y el maestro solo entre el 27 % y el 41 %. **El cuello de botella es el esclavo.**

Cada imagen de carrera tiene unos **400 polígonos** visibles de mediana (entre 300 y 500 lo habitual, con picos de 600–700). A 30 FPS eso supone unos 12.000 polígonos por segundo, frente a unos 8.000 del original.

### 3.1 Reparto por bandas: `sh2/mdrv.s`

Es la mejora más grande. Cuando el maestro termina de publicar la lista de polígonos, en lugar de quedarse esperando al esclavo, entra en esta rutina:

- **Retira polígonos de la cola.** Cuenta cuántos polígonos no ha empezado todavía el esclavo. Si son menos de 24, no compensa y sale. Si hay suficientes, deja 3 de margen y retira el resto de la cola, marcándolos con estado 0.
- **Los reparte según una línea de corte.** Para cada polígono retirado:
  - Si queda entero por encima de la línea, se lo devuelve al esclavo tal cual.
  - Si queda entero por debajo, lo pinta el maestro y el esclavo recibe una copia vacía.
  - Si cruza la línea, lo recorta: el esclavo recibe la parte de arriba y el maestro pinta la de abajo.
- **Mantiene el orden de pintado.** Cada banda la pinta un solo procesador, en el mismo orden que el original. Antes de empezar, el maestro espera una única vez a que el esclavo termine el último polígono que no se retiró.
- **No compite por el circuito de relleno.** Solo hay uno y lo sigue usando el esclavo en exclusiva. El maestro pinta con escrituras directas del procesador (`msolid`), usando su propia copia del rasterizador del juego (`0x306800`, copiado de `0x23A70`). En esa copia se han quitado las cuatro purgas de caché y se han redirigido las dos llamadas de relleno.
- **La línea de corte se ajusta sola.** Empieza en la línea 140 y al final de cada imagen se mueve 4 líneas según quién haya terminado antes:
  - Si el esclavo acabó primero, el maestro iba cargado: le toca una banda más pequeña.
  - Si al esclavo aún le quedaban más de 4 polígonos, el maestro iba sobrado: le toca una banda más grande.

  Siempre queda entre la línea 40 y la 200.

Conexión: el literal `0x0600122C` (el que usa el maestro para la espera final) pasa a apuntar a `0x02306000`. La rutina termina saltando a la espera original (`06004438`).

### 3.2 Borrado de líneas con la CPU: `sh2/cclr.s`

La rutina `060044F6` borra líneas con el circuito de relleno. Por cada línea programa el relleno, ejecuta un bucle de espera fijo y después consulta el registro FEN hasta que el relleno termina. `cclr` escribe los ceros directamente con el procesador, sin esas esperas.

> **Fallo corregido en v7.** El juego pasa la dirección de la línea en `r1` con `mov.w`, así que las líneas de `$9400` en adelante llegan con signo negativo. El circuito de relleno solo usaba los 16 bits bajos y no le afectaba, pero `cclr` usaba el valor completo y escribía fuera de la pantalla. Con la cámara alejada, en zonas como una cresta de Big Forest, esas líneas se quedaban sin borrar y se veían restos, como el minimapa "arrastrado". La solución es un `extu.w`.

### 3.3 Borrado solapado con la transformación: `VR60_EXPERIMENTAL_SLAVE_CLEAR_OVERLAP`

En el original, el maestro borra un bloque de 320×100 píxeles, espera a que termine y solo entonces transforma los vértices. Ahora el esclavo hace ese mismo borrado (comando nuevo `$08`) mientras el maestro recibe el bloque de escena por FIFO y transforma los vértices. El resultado es idéntico: solo cambia el orden en el tiempo. Código: `disasm/sh2/expansion/vr60_slave_clear_overlap.s`.

### 3.4 Transformación de vértices: `VR60_EXPERIMENTAL_ONCHIP_VERTEX_*`

- **Memoria interna:** la parte más repetida de la rutina de vértices se ejecuta desde la memoria interna del SH2 (la zona de la caché que se puede usar como RAM). Cada vez que se restaura esa zona, una rutina auxiliar vuelve a copiar el código original y coloca la versión rápida.
- **Sin instrucciones sobrantes:** se han quitado los NOP y se han reordenado los saltos para aprovechar el hueco del *delay slot* (`..._NOP_REMOVE`, `..._BT_SCHEDULE`).
- **Desplazamientos en vez de multiplicaciones:** la rutina solo recibe dos escalas, 64 y 2048, que equivalen exactamente a desplazar 6 y 11 bits.

### 3.5 Preparación de líneas en una sola pasada: `VR60_EXPERIMENTAL_SCANLINE_PAIR_FUSED`

El rasterizador llamaba dos veces seguidas a `scanline_setup`, que recorre la misma tabla de 4 valores, primero hacia delante y luego hacia atrás. La versión nueva elige directamente cuál de las 16 combinaciones de inicio y fin toca y deja los registros exactamente como los dejaría la segunda llamada, sin pasar por la pila. Código: `disasm/sh2/expansion/vr60_scanline_pair_fused.s`.

### 3.6 Marcador cacheado: `sh2/hud9.s`

Los sprites de marcador de tipo 9 están comprimidos en RLE y se dibujaban de derecha a izquierda, byte a byte, en cada imagen. Ahora:

- Se descomprimen una vez y se guardan en SDRAM. Hay dos huecos, identificados por el gráfico de origen y por la alineación del destino.
- En cada imagen se copian con escrituras de 4 bytes sobre la vista del framebuffer en la que los bytes a cero no se escriben, así que la transparencia sale igual que con el bucle original.
- Si un sprite no cabe en la caché, se dibuja con la rutina original.

El salto a esta rutina está en los 12 NOP que el comando `$02` original tenía libres (`6000D10`–`6000D27`).

### 3.7 Menos datos entre el 68000 y la 32X

- **Solo la cámara (`sh2/h3dc.s`, comando del maestro `$3D`, `VR60_30_CAMONLY`):** en las imágenes intermedias la escena no cambia, solo la cámara interpolada. El 68000 envía únicamente los 120 bytes de la cámara en vez del bloque de escena completo. El único valor de fuera de ese bloque que cambia, `$FF674C`, se pasa por COMM4.
- **Orden del comando `$02`:** el comando de dibujo normal prepara la geometría antes del punto en que espera al esclavo, igual que ya hace el manejador `$3F`.

---

## 4. Treinta imágenes con veinte estados (68000)

### Planificador: `VR60_EXPERIMENTAL_30FPS_SCHED`

El 68000 lanza un dibujo cada 2 refrescos de pantalla (30 por segundo), mientras la lógica sigue avanzando cada 3 (20 por segundo). Por eso las imágenes caen entre dos estados del juego. Opciones relacionadas:

| Opción | Qué hace |
|---|---|
| `VR60_30_EARLY_AUTH`, `VR60_30_AUTH3F` | Lanzan el dibujo lo antes posible dentro de cada paso de lógica. |
| `VR60_30_PRESENT_WAIT=220` | Espera acotada antes de presentar la imagen terminada. |
| `VR60_30_VBLANK_GUARD` | Evita cambiar de búfer fuera del retrazado vertical. |
| `sh2/fsw.s` | Un dibujo no empieza hasta que el cambio de búfer pendiente se ha hecho, así que nunca se pinta sobre la imagen que se está mostrando. |
| `VR60_30_DEMO` | La demo de la pantalla de título también va a 30 FPS. No se interpola a través de los cortes de cámara de la repetición, y usa el comando de escena original (`$05`). |

### Interpolación

- **Cámara:** en cada imagen se mezcla el estado anterior con el actual con un factor de 0, 1/3 o 2/3, según en qué punto entre los dos cae la imagen.
- **Coches rivales: `VR60_30_CARS`, `modules/68k/vint/vr60_30fps_cars.asm`.** Sus posiciones y ángulos (`+$12`/`+$14`/`+$16` y `+$18`/`+$1A` de cada objeto en `$FF61CC`) se mezclan con el mismo factor, para que no vayan un paso por delante de la cámara y den saltitos. Si la diferencia entre dos estados supera ±`$1000` (reaparición del coche o reutilización del hueco), se usa el valor actual sin mezclar.
- **Ángulos: `VR60_30_ANGLE_WRAP`, `VR60_30_HEADING_WRAP`.** Los ángulos se mezclan por el camino corto al pasar de 359° a 0°. Sin esto, en el punto del circuito donde el ángulo da la vuelta (por ejemplo, el puente de Big Forest) una imagen giraba unos 120° en sentido contrario.

**Coste:** la cámara va hasta un paso de lógica por detrás (50 ms como máximo). Es la técnica habitual para mostrar más imágenes de las que genera la lógica.

---

## 5. Estabilidad en emuladores: `pwpatch.py`, `sh2/pw.s`

- **Esperas reescritas:** algunas versiones del recompilador de PicoDrive pueden dejar dormido para siempre a un SH2 que espera un cambio en SDRAM. Cuatro bucles de espera de la cola se sustituyen por versiones que no disparan ese problema.
- **Selección de coche:** se restaura el envío original del comando `$22`, para que la selección de coche vaya exactamente como en el juego original.

---

## 6. Cómo se ha verificado

Todo se ha probado en PicoDrive (libretro) con entradas grabadas, que se reproducen idénticas en cada ejecución:

- **Imágenes por segundo:** se cuentan las imágenes distintas por segundo en la zona 3D. En carrera se mantienen casi siempre en 30, con algunas muestras más bajas que no se han revisado una a una. La demo va a unos 30.
- **Estabilidad:** carrera completa de 16.000 frames sin ningún SH2 bloqueado.
- **Imagen:** comparación con la ROM original en los mismos puntos del circuito, con la cámara normal y con la alejada.
- **Búsqueda de fallos:** se guarda el estado del emulador y se repite el mismo tramo con cada optimización desactivada por separado. Así se localizó el fallo de `cclr` (sección 3.2).

**Pendiente de comprobar:** hardware real, Ares y el modo de 2 jugadores.

---

## 7. Mapa de ficheros

| Fichero | Contenido |
|---|---|
| `experiments/fps30/build_vr30.sh` | Construcción completa |
| `experiments/fps30/make_band_rom.py` | Inserción de las rutinas SH2 y parches de la ROM |
| `experiments/fps30/pwpatch.py` | Esperas para PicoDrive y restauración del comando `$22` |
| `experiments/fps30/sh2/mdrv.s` | Reparto por bandas (maestro) |
| `experiments/fps30/sh2/cclr.s` | Borrado de líneas con la CPU |
| `experiments/fps30/sh2/hud9.s` | Marcador cacheado |
| `experiments/fps30/sh2/h3dc.s` | Comando `$3D`: envío solo de la cámara |
| `experiments/fps30/sh2/fsw.s` | Espera al cambio de búfer antes de empezar a dibujar |
| `experiments/fps30/sh2/pw.s` | Bucles de espera para PicoDrive |
| `disasm/modules/68k/vint/vr60_1p_interpolated_render.asm` | Planificador de 30 FPS e interpolación de cámara (68000) |
| `disasm/modules/68k/vint/vr60_30fps_cars.asm` | Interpolación de los coches rivales |
| `disasm/modules/68k/vint/vint_unified_60fps.asm` | Presentación de imágenes y reinicio del estado de 30 FPS |
| `disasm/modules/68k/game/state/state_disp_005586.asm`, `game/scene/frame_update_orch_0055d0.asm` | Demo a 30 FPS |
| `disasm/sh2/expansion/vr60_*.s` | Optimizaciones SH2 del ensamblado principal (secciones 3.3–3.5) |

`VR60_30_DBG_NOLAG` es una opción solo de diagnóstico, desactivada por defecto: hace que la cámara use el último estado de lógica, sin retraso.
