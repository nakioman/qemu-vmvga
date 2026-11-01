# RetroBox build of qemu-vmvga

This branch packages QEMU with the vmvga device for
[RetroBox](https://github.com/nakioman/retro-pc), a Debian 13 retro PC
appliance. It runs a Windows XP guest under KVM with VMware's SVGA II
driver: 32-bit 2D, Direct3D through SVGA3D rendered by dxvk-native on the
host's Vulkan driver, and QEMU's GTK display scaling on the GPU.

`master` mirrors [qemus/qemu-vmvga](https://github.com/qemus/qemu-vmvga);
RetroBox changes live on the `retrobox` branch.

## Changes to vmvga (commits on this branch)

- `hwcursor=off`: VMware guests only report hardware cursor positions with an
  absolute pointer (vmmouse). With the relative PS/2 mouse games need, the
  pointer stayed at 0,0; without the capability the guest draws its own.
- `gbobjects=off`: the XP driver's screen-target path left a stale buffer on
  screen after mode switches; the classic framebuffer and screen-object model
  switches modes correctly.
- 15/16 bpp guest modes are accepted, so XP offers 16-bit modes (DirectX 7
  era titles request 640x480x16).

## QEMU patches (`retrobox/patches/`)

- `0001-gtk-fullscreen-force-4-3.patch`: fullscreen output is a centred 4:3
  box for every guest mode (the 720x400 text mode included), like a CRT.
- `0003-gtk-gl-fullscreen-force-4-3.patch`: the same 4:3 box for the
  OpenGL paths (`gl=on`), which set their own viewport.
- `0002-gtk-fullscreen-grab-input.patch`: with `grab-on-hover=on` in
  fullscreen, keyboard and pointer are captured from the start, so host
  shortcuts such as Alt+F4 reach the guest.

- `0004-ac97-keep-volume-across-voice-reopen.patch`: the AC97 codec's Master
  and PCM Out volume are reapplied when the guest changes sample rate; before,
  a reopened voice played at full volume and XP's master volume and mute had
  no effect.

## Build

On Debian 13 amd64, or anywhere with Docker:

```bash
docker run --rm --platform linux/amd64 -v "$PWD:/src" -w /src \
    debian:trixie retrobox/build.sh --install-deps
```

`retrobox/out/qemu-retrobox-<qemu>-<rev>-linux-x86_64.tar.gz` unpacks to
`/opt/qemu-retrobox`: QEMU (`i386-softmmu`, GTK + OpenGL, no SDL) and
dxvk-native in `lib/`. QEMU dlopens DXVK, so run it with
`LD_LIBRARY_PATH=/opt/qemu-retrobox/lib`.

Pinned inputs are in `retrobox/versions.env`.

## Running

```text
-machine pc,accel=kvm,vmport=on
-vga none -device vmvga,hwcursor=off,gbobjects=off,vgpu=9
-display gtk,gl=on,full-screen=on,show-menubar=off,show-tabs=off,
         zoom-to-fit=on,grab-on-hover=on,window-close=off
```

Host requirements (Debian 13): Xorg with a window manager that honours
fullscreen requests (RetroBox uses `matchbox-window-manager`), GTK 3,
`libvulkan1` and `mesa-vulkan-drivers`, and KVM loaded with
`enable_vmware_backdoor=1`; otherwise the guest driver disables Direct3D.
The guest needs VMware's SVGA II driver for Windows XP, which is not
distributed here.

## Releases

GitHub Actions (`.github/workflows/retrobox.yml`) builds every push to
`retrobox` and attaches the package to a release for `retrobox-*` tags.

## Updating

```bash
git fetch upstream
git checkout master && git merge --ff-only upstream/master && git push
git checkout retrobox && git merge master
```
