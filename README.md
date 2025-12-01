# Raspberry Pi 5 Talos Builder
This repository serves as the glue to build custom Talos images for the Raspberry Pi 5. It patches the Kernel and Talos build process to use the Linux Kernel source provided by [raspberrypi/linux](https://github.com/raspberrypi/linux).

## Tested on
So far, this release has been verified on:

| ✅ Hardware                                                |
|------------------------------------------------------------|
| Raspberry Pi Compute Module 5 on Compute Module 5 IO Board |
| Raspberry Pi Compute Module 5 Lite on [DeskPi Super6C](https://wiki.deskpi.com/super6c/) |
| Raspberry Pi 5b with [RS-P11 for RS-P22 RPi5](https://wiki.52pi.com/index.php?title=EP-0234) |

## What's not working?
* Booting from USB: USB is only available once LINUX has booted up but not in U-Boot.

## How to use?
The releases on this repository align with the corresponding Talos version. There is a raw disk image (initial setup) and an installer image (upgrades) provided.

### Examples
Initial:
```
unzstd metal-arm64-rpi.raw.zst
dd if=metal-arm64-rpi.raw of=<disk> bs=4M status=progress
sync
```

Upgrade:
```
talosctl upgrade \
  --nodes <node IP> \
  --image ghcr.io/talos-rpi5/installer:<version>
```

## Building

If you'd like to make modifications, it is possible to create your own build. Bellow is an example of the standard build. The Makefile needs the model specifying in order to label the produced images properly, model should be `rpi4` or `rpi5`.

On a Mac use `gmake` not `make` and set `SED=gsed` on the command line

```
# To build all assets from the kernel up to the installer for the RPi4
make RPI_MODEL=<model> pi4

# For the pi5 installer image
make RPI_MODEL=<model> pi5

# For the pi5 installer image on Mac
gmake RPI_MODEL=<model> SED=gsed pi5

# To make SD card images set ASSET_TYPE=metal
make RPI_MODEL=<model> ASSET_TYPE=metal pi5
```

## License
See [LICENSE](LICENSE).
