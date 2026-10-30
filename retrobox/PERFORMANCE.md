# vgpu9 performance plan

Findings from profiling a Windows XP guest (VMware SVGA II XPDM driver,
`vmvga,hwcursor=off,gbobjects=off,vgpu=9`) on an Intel UHD 730 with
dxvk-native 3.1.1, plus a source review of `hw/display/`. DXVK itself is not
the bottleneck: its threads stay nearly idle while the QEMU main thread
saturates in vmvga's glue around it. Keep D3D9-on-DXVK as the vgpu9 backend.

Symptoms: 3DMark03/06 slow; guest frame counters report hundreds of fps while
the display lags or freezes; one guest vCPU at 100% during 3D.

## Done

- Clears: skip the CPU shadow clear when the D3D9 clear runs on the GPU
  (`perf: skip CPU shadow clears ...`).

## Batch 1: redundant CPU work (low risk)

1. **Buffer DMA uploads in place.** Legacy SURFACE_DMA into a resident vertex
   or index buffer takes the CPU-only plan (`vmsvga3d_d3d9_dma_plan`), then
   `vmsvga3d_dxvk_sync_surface_from_cpu` evicts non-texture surfaces, so every
   dynamic buffer update releases the D3D9 buffer and the next draw recreates
   it and uploads all of `storage_bytes`. Upload the written range in place
   instead, and honour the DMA suffix flags: `discard` -> D3DLOCK_DISCARD with
   the full shadow, `unsynchronized` -> D3DLOCK_NOOVERWRITE on the range.
   Buffers are input-only, so the shadow stays authoritative.
2. **StretchBlt** reads the whole destination back after the GPU blit; drop
   it (resident destination, CPU users read back on demand).
3. **SurfaceCopy** mirrors each box into the destination shadow after the GPU
   copy; drop it for the same reason.
4. **Texture DMA writes** upload the whole mip level; upload only the boxes.
   This also fixes partial writes into GPU-written textures wiping GPU pixels.

## Batch 2: pacing and display (medium risk)

5. **SVGA_REG_BUSY reads** run `vmsvga_fifo_run` (up to 1024 commands) on the
   vCPU thread. Only schedule the FIFO bottom half there.
6. **Fences** are published when parsed, not when the GPU finishes, and the
   GPU present path bypasses DXVK's frame limiter, so the guest runs ahead
   bounded only by the 2 MiB FIFO. Publish fences after a D3D9 event query
   signals, and cap outstanding frames at 2-3. Wrap-aware FENCE_GOAL test.
7. **Screen Object present** does a full synchronous readback per blit and
   three or four 3 MiB copies. Read back only the clip rects straight into
   BAR1, then make it asynchronous (one frame late) using the screen-target
   readback ring. Software cursor (`hwcursor=off`) reads BAR1 directly, so the
   deferred readback must be completed before guest BAR1 access paths.

## Batch 3: structural (weeks)

8. Dedicated render thread owning the DXVK device (VirtualBox model); SYNC and
   BUSY only signal it.
9. Zero-copy display via dmabuf (`dpy_gl_scanout_dmabuf`); modest gain after
   7, only for unclipped full-screen blits.

Also to check: BeginScene/EndScene is issued per draw; per frame may avoid
DXVK command buffer flushes.

Test after each step: dxdiag D3D7/8/9 tests, 3DMark2001 SE, 3DMark03,
3DMark06, Quake III (OpenGL ICD), for speed and rendering corruption.
