# bluetoothpatch

Out-of-tree Linux kernel module que recompila el driver `btusb` con soporte para un dispositivo MediaTek específico (`USB_DEVICE(0x04ca, 0x3807)`) que no está incluido en el árbol oficial del kernel.

Incluye integración con **pacman** para recompilación automática al actualizar los headers del kernel.

---

## El problema

El adaptador Bluetooth MediaTek `04ca:3807` no tiene entrada en la tabla de IDs del driver `btusb` del kernel oficial. Sin este parche, el dispositivo no es reconocido y el Bluetooth no funciona.

## Solución

Se recompila `btusb.c` con la entrada añadida:

```c
/* MediaTek MT7921 */
{ USB_DEVICE(0x04ca, 0x3807), .driver_info = BTUSB_MEDIATEK |
  BTUSB_WIDEBAND_SPEECH | BTUSB_VALID_LE_STATES },
```

El módulo resultante reemplaza al original del sistema. Un hook de pacman garantiza que el parche se reaaplica automáticamente cada vez que se actualiza el kernel.

---

## Kernels soportados

| Sabor | Paquete de headers | Repositorio de fuentes |
|---|---|---|
| `linux-zen` | `linux-zen-headers` | zen-kernel/zen-kernel |
| `linux-lqx` | `linux-lqx-headers` | zen-kernel/zen-kernel |
| `linux-hardened` | `linux-hardened-headers` | anthraxx/linux-hardened |
| `linux-lts` | `linux-lts-headers` | gregkh/linux |
| `linux-rt` / `linux-rt-lts` | `linux-rt-headers` | gregkh/linux |
| `linux` (mainline Arch) | `linux-headers` | gregkh/linux |

Si el tag del sabor no está disponible en su repositorio primario, el script usa `gregkh/linux` como fallback automático.

---

## Requisitos

- Arch Linux (o derivado) con pacman
- Headers del kernel instalados (ver tabla anterior)
- `curl`, `zstd`, `make`, `gcc`

---

## Instalación manual

```bash
# Clonar el repositorio
git clone https://github.com/waldaldo/mediatek-fix.git
cd bluetoothpatch

# Compilar e instalar (requiere root)
sudo ./apply-patch.sh
```

El script:
1. Detecta el kernel y sabor en ejecución (`uname -r`)
2. Verifica que los headers estén instalados
3. Descarga los headers internos del subsistema bluetooth desde el repositorio fuente correspondiente
4. Compila el módulo contra el kernel actual
5. Hace backup del módulo original como `btusb.ko.zst.orig`
6. Instala el módulo parcheado y reinicia `bluetooth.service`

---

## Hook de pacman (recompilación automática)

Instala el hook y el script para que el parche se aplique solo en cada actualización del kernel:

```bash
# Copiar fuentes a la ruta estándar
sudo mkdir -p /usr/local/src/btusb-patch
sudo cp btusb.c compat.h /usr/local/src/btusb-patch/

# Instalar el script de build
sudo cp install-btusb-patch.sh /usr/local/bin/install-btusb-patch
sudo chmod +x /usr/local/bin/install-btusb-patch

# Instalar el hook de pacman
sudo mkdir -p /etc/pacman.d/hooks
sudo cp btusb-patch.hook /etc/pacman.d/hooks/
```

A partir de ese momento, al actualizar cualquier paquete `*-headers` soportado, pacman ejecutará `install-btusb-patch` automáticamente.

---

## Estructura del proyecto

```
bluetoothpatch/
├── btusb.c                  # Driver btusb parcheado
├── compat.h                 # Shims de compatibilidad entre versiones del kernel
├── Makefile                 # Build out-of-tree del módulo
├── apply-patch.sh           # Script de instalación manual
├── install-btusb-patch.sh   # Script llamado por el hook de pacman
└── btusb-patch.hook         # Hook de pacman
```

Los headers `btintel.h`, `btbcm.h`, `btrtl.h` y `btmtk.h` se descargan en tiempo de compilación desde el repositorio fuente del kernel correspondiente y no se incluyen en el repositorio.

---

## Restaurar el módulo original

```bash
KVER=$(uname -r)
DEST="/lib/modules/${KVER}/kernel/drivers/bluetooth"
sudo cp "${DEST}/btusb.ko.zst.orig" "${DEST}/btusb.ko.zst"
sudo depmod -a
sudo systemctl restart bluetooth
```
