# GPU through Venus: device test checklist

Target device: Pixel 10 Pro (Tensor G5, PowerVR DXT-48-1536). The same build
should work on Mali phones (Pixel 6 to 9, Exynos, MediaTek); untested so far.

## How it works

Linux apps use Mesa's Venus Vulkan driver (`VN_DEBUG=vtest`). It sends their
Vulkan commands over `/tmp/.virgl_test` to the Venus server in the APK, whose
render server runs them on Android's own Vulkan driver. OpenGL apps go through
Zink, which turns OpenGL into Vulkan on top of Venus. Finished frames are
copied into the X server (`MESA_VK_WSI_DEBUG=sw`), so expect it to be faster
than software rendering for 3D work but not native speed.

GPU memory is shared with the server in one of two ways. **dma-buf** is
upstream Venus and needs `VK_EXT_external_memory_dma_buf` (the Pixel 10 Pro has
it). **AHardwareBuffer** is a separate server build for drivers that lack it,
common on Mali. Automatic asks the driver and picks one.

KWin (window effects) stays on software rendering by default, because virgl
crashed it. Apps get the GPU either way.

## Results so far

- 2026-10-23, Pixel 10 Pro, virgl (the previous approach): KWin crashed
  repeatedly and a Firefox tab crashed. Replaced by Venus.
- GPU report (Android 17, driver 25.3@6908880): Vulkan 1.4.317, and every
  extension Venus needs is present, including `VK_KHR_external_memory_fd`,
  `VK_EXT_external_memory_dma_buf` and `VK_EXT_image_drm_format_modifier`.
- Firefox tabs crash in software mode too, so that crash isn't the GPU path's.

## 1. GPU report (before starting the desktop)

Settings → **GPU report** → **Share**, and send the text back. Check the lines
"Venus server: bundled", "Venus driver in system image: virtio_icd…" and the
Venus memory mode Automatic picked.

## 2. Desktop with Venus

1. Settings → Graphics: **GPU via Venus (experimental)**. GPU memory: **Automatic**.
   Leave "Desktop effects on the GPU" off.
2. Start the desktop. The status line should say "GPU via Venus (experimental)".
3. In Konsole:
   - `vulkaninfo --summary`: expect a device named `Virtio-GPU Venus (PowerVR …)`.
   - `glxinfo -B`: expect `OpenGL renderer string: zink Vulkan 1.x (Virtio-GPU Venus …)`.
   If either shows `llvmpipe`, open Settings → Log and look for `[venus]` lines.
4. Check, with notes on smoothness compared with software rendering:
   - [ ] `vkcube` runs and spins.
   - [ ] `glxgears` frame rate (compare with Graphics → Software).
   - [ ] Firefox: `about:support` → Compositing; try a WebGL page such as the WebGL Aquarium.
   - [ ] A video in Firefox or VLC.
   - [ ] Desktop: drag windows, open the launcher, Overview (Meta+W). Should be unchanged.
   - [ ] External monitor (USB-C), same checks.
5. If step 4 works, try "Desktop effects on the GPU" on and repeat the desktop
   check. If apps crash or draw garbage, try GPU memory **AHardwareBuffer**.

## 3. If something breaks

- Graphics → **Software (llvmpipe)** brings back the Phase 1 behaviour.
- Settings → Log → **Share log**, and send the lines starting with `[venus]` and `[session]`.
