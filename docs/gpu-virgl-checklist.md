# GPU through virgl: device test checklist

Target device: Pixel 10 Pro (Tensor G5, PowerVR DXT-48-1536). The same build
should work on Mali phones (Pixel 6 to 9, Exynos, MediaTek); untested so far.

## How it works

Linux apps use Mesa's virgl driver (`GALLIUM_DRIVER=virpipe`). It sends their
OpenGL work over `/tmp/.virgl_test` to the virgl server in the APK, which
renders it with Android's GPU driver: the system's ANGLE when the phone has it
(Automatic), or the vendor's OpenGL ES. Finished frames are copied back into
the X server, so expect it to be smoother than software rendering but not native
speed. Vulkan apps still use software rendering until Venus lands.

## Results so far

- 2026-10-23, Pixel 10 Pro, Automatic (ANGLE): KWin crashed repeatedly ("KWin is
  unstable") and a Firefox tab crashed. Software rendering works well. Since
  then: Automatic picks software on non-Adreno phones, virgl is opt-in, and in
  virgl mode KWin composites in software while apps use the GPU.

## 1. GPU report (before starting the desktop)

Settings → **GPU report** → **Share**, and send the text back. It shows the GPU,
the OpenGL ES and ANGLE versions, and which Vulkan extensions the driver has.
The "forwarding checks" block decides how much work Venus (the next step) needs.

## 2. Desktop with virgl

1. Settings → Graphics: **GPU via virgl (experimental)**. Virgl backend: **Automatic**.
2. Start the desktop. The status line should say "GPU via virgl (experimental)".
3. In Konsole: `glxinfo -B`. Expected: `OpenGL renderer string: virgl (...)`.
   If it says `llvmpipe`, open Settings → Log and look for `[virgl]` lines.
4. Check, with notes on smoothness compared with software rendering:
   - [ ] Desktop effects: drag windows around, open the app launcher, Overview (Meta+W).
   - [ ] `glxgears` frame rate (compare with Graphics → Software).
   - [ ] Firefox: `about:support` → Compositing should say WebRender (not Software);
         try a WebGL page such as the WebGL Aquarium.
   - [ ] A video in Firefox or VLC.
   - [ ] External monitor (USB-C), same checks.
5. Repeat step 4 with Virgl backend **ANGLE** and **Vendor GLES** if
   Automatic shows problems (black windows, flicker, crashes). Note which is better.

## 3. If something breaks

- Graphics → **Software (llvmpipe)** brings back the Phase 1 behaviour.
- Settings → Log: copy the lines starting with `[virgl]` and `[session]`.
