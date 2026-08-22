# MSXDOS4Agon

## MSX-DOS High Level Emulator for Agon MOS

**[English Version](#english-version) | [Versión en Español](#versión-en-español)**

---

<a id="english-version"></a>

## English Version

More information at [Minibots]().

High-Level Emulator (HLE) developed entirely in eZ80 assembly for **Agon Light**. It allows running the original MSX-DOS 1 command interpreter (`COMMAND.COM`) and classic MSX-DOS and CP/M 2.2 applications natively, translating system requests to the host operating system (Agon MOS).

### Key Features

* **Strict HLE Emulation:** Does not simulate MSX motherboard hardware (like the VDP video chip or ROM BIOS). Instead, it presents a "perfect computer" that responds exclusively to the operating system API (BDOS).
* **Compatibility:** Capable of running complex transient programs (`.COM`) like `UNARJ.COM`, `PMEXT.COM`, or classic utilities like `COPY` and `DIR`, supporting massive read/write cycles and CRC validation.
* **Sandboxed File System:** Logical virtual drives (`A:` and `B:`) are safely mapped to physical directories on the Agon's microSD card (`/MSXDOS/A` and `/MSXDOS/B`), translating historical FCB (File Control Block) structures on the fly to the modern FatFs system.
* **Warm Boot:** Captures clean program exits (jumps to `$0000`, or BDOS functions `00h` and `62h`) to clean the virtual environment and reload `COMMAND.COM` without crashing the host system.
* **Anti-Crash Protection:** Calls to unimplemented functions, exclusive MSX-DOS 2 calls, or attempts to jump directly to MSX ROM routines (e.g., `$001C`) are intercepted and safely handled.

### Three-Tier Architecture

The system is logically divided into three separate layers to maximize performance and safety:

1. **Virtual Level (Z80 Engine):** Contained in `z80_cpu.asm`, it maintains the exact state of the registers (`CPU_AF`, `CPU_HL`, etc.) and manages 64 KB of virtual flat RAM (`MSX_RAM`). 
2. **Interceptor Level (BDOS Handler):** Monitors the virtual Program Counter (PC). If it detects a jump to the `$0005` vector, it suspends virtual execution and transfers control to `MSX_BDOS_Hook` to evaluate the requested service.
3. **Translation Level (Agon MOS):** Transforms the intercepted call into real calls to the Agon Light API, translating random reads/writes into `mos_flseek` and `mos_fread` calls and managing a secure handle table.

### Project Structure

* `msxdos.asm`: Program entry point. Contains the main loop, sandbox initialization, BDOS handler (`MSX_BDOS_Hook`), and FatFs/MOS translation routines.
* `z80_cpu.asm`: The pure Z80 processor emulation core, including opcode decoding, software ALU, and jump management.

### Known Limitations

* **MSX Graphics:** Programs attempting to draw on the screen by calling VDP subroutines or MSX BIOS routines will not work correctly.
* **MSX-DOS 2:** The emulator is restricted by design to MSX-DOS 1. Applications exclusive to DOS 2.x will fail.

### Installation and Use

For the compilation:

1. `ez80asm msxdos.asm msxdos.bin`

2. Copy `msxdos.bin` into the root directory of your Agon Light's microSD card.

For the deployment:

1. Create the directories `/MSXDOS/A` and `/MSXDOS/B` on your Agon Light's microSD card.
2. Copy the original `COMMAND.COM` binary (version 1.x) and your `.COM` applications into `/MSXDOS/A`.
3. Run the emulator from the Agon MOS terminal.

### Requirements

* **Agon Light** (tested on **Olimex AgonLight2**) or compatible hardware (like Agon Console8).
* **Agon MOS 3.x** or higher (required for extended FatFs API calls like `mos_flseek` or `mos_ren`).
* An eZ80 assembler (e.g., `ez80asm`) to compile the source code. 

### License

This project is licensed under the **GNU General Public License v2.0**. See the `LICENSE` file for more details.

---

<a id="versión-en-español"></a>

## Versión en Español

Más información en [Minibots]().

Emulador de alto nivel (HLE) desarrollado íntegramente en ensamblador eZ80 para **Agon Light**. Permite ejecutar el intérprete de comandos original de MSX-DOS 1 (`COMMAND.COM`) y aplicaciones clásicas de MSX-DOS y CP/M 2.2 de forma nativa, traduciendo las peticiones del sistema al sistema operativo anfitrión (Agon MOS).

### Características Principales

* **Emulación HLE Estricta:** No simula el hardware de la placa base del MSX (como el chip de vídeo VDP o la BIOS en ROM). En su lugar, presenta un "ordenador perfecto" que responde exclusivamente a la API del sistema operativo (BDOS).
* **Compatibilidad:** Capaz de ejecutar programas transitorios complejos (`.COM`) como `UNARJ.COM`, `PMEXT.COM` o utilidades clásicas como `COPY` y `DIR`, soportando ciclos masivos de lectura/escritura y validación de CRC.
* **Sistema de Archivos Sandboxed:** Las unidades virtuales lógicas (`A:` y `B:`) se mapean de forma segura a directorios físicos en la tarjeta microSD del Agon (`/MSXDOS/A` y `/MSXDOS/B`), traduciendo al vuelo los bloques FCB (File Control Block) históricos al sistema FatFs moderno.
* **Warm Boot (Reinicio en Caliente):** Captura las salidas limpias de los programas (saltos a `$0000`, o funciones BDOS `00h` y `62h`) para limpiar el entorno virtual y recargar `COMMAND.COM` sin colgar el sistema anfitrión.
* **Protección Anti-Crash:** Las llamadas a funciones no implementadas, exclusivas de MSX-DOS 2, o intentos de saltar directamente a rutinas de la ROM del MSX (ej. `$001C`) son interceptadas y gestionadas de forma segura.

### Arquitectura en Tres Niveles

El sistema se divide lógicamente en tres capas separadas para maximizar el rendimiento y la seguridad:

1. **Nivel Virtual (Motor Z80):** Contenido en `z80_cpu.asm`, es una máquina virtual que mantiene el estado exacto de los registros (`CPU_AF`, `CPU_HL`, etc.) y gestiona 64 KB de RAM plana virtual (`MSX_RAM`). Ejecuta las instrucciones emulando el comportamiento exacto de los *flags* originales.
2. **Nivel Interceptor (Gestor BDOS):** El bucle de ejecución vigila el Contador de Programa (PC) virtual. Si detecta un salto al vector `$0005`, suspende la ejecución virtual y transfiere el control a `MSX_BDOS_Hook` para evaluar el servicio solicitado.
3. **Nivel de Traducción (Agon MOS):** Transforma la llamada interceptada en llamadas reales a la API del Agon Light. Por ejemplo, traduce lecturas aleatorias (`F_READRAND` `21h` o bloques `27h`) en llamadas `mos_flseek` y `mos_fread` gestionando internamente una tabla de *handles* segura.

### Estructura del Proyecto

* `msxdos.asm`: Punto de entrada del programa. Contiene el bucle principal, la inicialización del *sandbox*, el gestor BDOS (`MSX_BDOS_Hook`), y las rutinas de traducción FatFs/MOS.
* `z80_cpu.asm`: El núcleo de emulación puro del procesador Z80, incluyendo la decodificación de *opcodes*, la ALU por software y la gestión de saltos.

### Limitaciones Conocidas

* **Gráficos MSX:** Los programas que intenten dibujar en pantalla llamando a subrutinas del VDP o rutinas de BIOS del MSX no funcionarán correctamente, ya que el emulador solo intercepta la salida estándar a través de BDOS (`02h`, `09h`, etc.).
* **MSX-DOS 2:** El emulador se restringe por diseño a MSX-DOS 1. Las aplicaciones exclusivas de DOS 2.x (como utilidades de subdirectorios) fallarán al devolver la versión de forma estricta.

### Instalación y Uso

Para la compilación:

1. `ez80asm msxdos.asm msxdos.bin`

2. Copia `msxdos.bin` al directorio raíz de la tarjeta microSD de tu Agon Light.

Para el despliegue:

1. Crea los directorios `/MSXDOS/A` y `/MSXDOS/B` en la tarjeta microSD de tu Agon Light.

2. Copia el binario original de `COMMAND.COM` (versión 1.x) y tus aplicaciones `.COM` dentro de `/MSXDOS/A`.

3. Ejecuta el emulador desde la terminal del Agon MOS.

### Requisitos

* **Agon Light** (probado en **Olimex AgonLight2**) u otro hardware compatible (como Agon Console8).
* **Agon MOS 3.x** o superior (necesario para las llamadas extendidas de la API FatFs como `mos_flseek` o `mos_ren`).
* Un ensamblador eZ80 (ej. `ez80asm`) para compilar el código fuente.

### Licencia

Este proyecto está licenciado bajo la **GNU General Public License v2.0**. Puedes consultar el archivo `LICENSE` para más detalles.