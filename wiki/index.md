# Index

Read this file first when navigating the wiki.

## Sources

- [[wiki/sources/anthropic-scaling-managed-agents]] - Source note for Anthropic's Managed Agents architecture post, covering session logs, harness/sandbox decoupling, credential vaulting, lazy sandbox provisioning, and many brains/many hands.
- [[wiki/sources/herohua-managed-agents-architecture]] - Source note for Ying Hua's OS-lens interpretation of Managed Agents as a capability-style microkernel for agents.
- [[wiki/sources/intel-lga1700-learning-notes]] - Source note for jjshao's Intel LGA 1700 and open X86 motherboard learning notes, covering socket signal groups, CPU/PCH routing, memory pins, and CPU power sense observations.
- [[wiki/sources/karpathy-llm-wiki]] - Source note for Andrej Karpathy's canonical `LLM Wiki` gist, the seed source for this vault.
- [[wiki/sources/obsidian-cli-help]] - Source note for Obsidian's CLI documentation, focused on vault-aware automation and inspection.

## Inspections

- [[wiki/inspections/opencode-console-benchmark-evaluation-data-model]] - 解释 console benchmark/evaluation JSON model：一个 benchmark row 存 `model`、`agent` 和 loose `result` JSON，里面包含 task aggregates、repeated runs、score details 和 judge rationales，并记录 duplicated model/agent fields 与 commit semantics 的 ambiguity。
- [[wiki/inspections/opencode-session-concurrent-prompt-instances]] - Explains that OpenCode session prompt serialization is process-local: one instance reuses/waits on an in-memory runner, while multiple instances can concurrently write prompts and run assistant loops against the same session.
- [[wiki/inspections/opencode-session-revert-two-layer-semantics]] - Explains OpenCode session revert as two-layer state: file changes are reverted immediately, while messages DB cleanup is delayed until the pending revert is committed by a follow-up action.
- [[wiki/inspections/mesa-radv-graphics-queue-family-detection]] - Traces RADV 如何判断 `vkGetPhysicalDeviceQueueFamilyProperties2` 是否 expose graphics queue family, from `radv_graphics_queue_enabled()` down to `DRM_AMDGPU_INFO` `available_rings`.
- [[wiki/inspections/mesa-radv-init-dispatch-tables-layers]] - Summarizes how `init_dispatch_tables()` builds RADV-internal device dispatch layers, including runtime-gated SQTT hooks and the non-Windows-only `rmv` layer.
- [[wiki/inspections/libdrm-amdgpu-vamgr-address-space-split]] - Explains `amdgpu_vamgr.c` GPU VA splitting into canonical `low/high` and `32-bit/rest` buckets, plus `AMDGPU_VA_RANGE_REPLAYABLE` and `va_base_required` allocation behavior.
- [[wiki/inspections/linux-amdgpu-eviction-fence-userq-bo-move]] - Explains how amdgpu uses per-file eviction fences on BO `dma_resv` objects to create a user queue quiescent point before TTM/VM BO moves or validation proceed.
- [[wiki/inspections/linux-amdgpu-vm-pte-update-synchronization]] - 解释 amdgpu 普通 GPUVM PTE/TLB synchronization 如何依赖 job/fence boundary，而不是 CPU-style fine-grained TLB shootdown。
- [[wiki/inspections/linux-amdgpu-userq-bo-mmap-vs-eviction-manager]] - Contrasts CPU mmap BO synchronization via zap-and-refault with user queue BO GPU VA references that require eviction-manager quiescence before BO moves.
- [[wiki/inspections/linux-dma-resv-shared-buffer-sync]] - Explains `dma_resv` as a per-buffer `ww_mutex` plus `dma_fence` container for shared, asynchronous, pipelined, and movable DMA buffers, and why not every DMA user needs it.
- [[wiki/inspections/linux-idr-preload-purpose]] - Explains `idr_preload()` as the IDR-internal node preload path used before `spin_lock()`, so `idr_alloc(..., GFP_NOWAIT)` can avoid potentially sleeping allocation in the locked section.
- [[wiki/inspections/linux-rcu-grace-period-pointer-publication]] - Explains Linux RCU as pointer publication plus deferred reclamation, grounding grace periods in `rcu_assign_pointer()`, Tree RCU `qsmask` tracking, and preempted-reader bookkeeping.
- [[wiki/inspections/linux-rcu-child-reference-lifetime]] - Summarizes how RCU-published lookup structures can safely expose refcounted child objects, using `dma_resv_list` and `dma_fence` to show when immediate child `put` is safe.

## Concepts

- [[wiki/concepts/cache-coherence]] - Defines cache coherence as the per-location or cache-line hardware foundation for shared cached memory, separate from cross-location memory ordering.
- [[wiki/concepts/cpu-sense-pins-kelvin-remote-voltage-sense]] - Explains CPU `_SENSE` pins as Kelvin-connected remote voltage sense points measured by the VR controller, including VCCIN_AUX synchronous buck feedback and VCC/VSS open-circuit protection behavior.
- [[wiki/concepts/intel-lga1700-socket-signal-groups]] - Organizes Intel LGA 1700 socket pins into power/GND, CPU-PCH, PCIe, DDI, DDR memory, debug, and platform-control signal groups.
- [[wiki/concepts/drm-mm]] - Explains `drm_mm` as DRM's caller-owned-node range allocator for abstract address spaces and placement ranges.
- [[wiki/concepts/drm-vma-offset]] - Explains `drm_vma_offset` as the fake mmap offset-to-BO mapping layer built on `drm_mm`, including per-file access checks and the per-device namespace uncertainty.
- [[wiki/concepts/opencode-usage-tips]] - Collects practical OpenCode usage tips, including observed active-file context behavior not covered by official docs.

## Entities

- None yet.

## Projects

- [[wiki/projects/linux-drm-amdgpu]] - Reading map for Linux DRM/amdgpu GPU memory-management notes, including `dma_resv`, user queue eviction fences, BO mmap versus GPU VA references, GPUVM PTE/TLB synchronization, DRM allocator helpers, and libdrm amdgpu VA allocation.
- [[wiki/projects/opencode]] - Reading map for OpenCode as a project, currently covering session/revert semantics, prompt concurrency boundaries, workspace sync/event replay, and practical usage observations while leaving room for CLI, TUI, server, SDK, config, tools, permissions, and editor-integration notes.

## Syntheses

- [[wiki/syntheses/opencode-agent-switch-system-prompt-cache]] - 总结 OpenCode `agent switch` 和 `plan_exit`：当前实现会保留 prior messages，并用 last user message 的 `agent` 重新 assemble `system prompt`；这会影响 `prompt cache` 和 context coherence，也引出 timeline-style `system` control frames 对 future harness 的价值。
- [[wiki/syntheses/opencode-workspace-syncevent-sync]] - Explains OpenCode workspace and SyncEvent semantics: local git workspaces sharing one DB do not need remote sync, while remote workspaces exchange session event logs and replay them into their own DB projections.
- [[wiki/syntheses/cache-coherence-write-ownership-and-atomics]] - Explains writable cache-line ownership, ordinary store ordering, atomic RMW behavior, x86 atomic load/store code generation, and why coherence is mainly per-location.
- [[wiki/syntheses/cache-coherence-broadcast-scope]] - Explains why cache coherence does not require broadcasting every ordinary write to every core, contrasting local writes under ownership with snooping and directory-based protocols.
- [[wiki/syntheses/cpu-store-buffer-l1-cache-pipeline-ooo]] - Explains CPU store buffers as core-private queues for pending stores, distinguishing them from L1 D-cache and from purely out-of-order machinery.
- [[wiki/syntheses/cpu-write-combining-purpose]] - Explains CPU write combining as buffering and merging adjacent stores into larger external write transactions for framebuffer, device, and streaming-write workloads.
- [[wiki/syntheses/cpu-cache-coherence-vs-special-concurrent-instructions]] - Explains why hardware cache coherence is the usual foundation for shared-memory CPUs instead of relying on compiler-detected concurrent variables and special broadcast load/store instructions.
- [[wiki/syntheses/llm-wiki-process-retrospective]] - Reviews how this vault's LLM wiki workflow has diverged from Karpathy's source-ingest pattern toward code sources, project hubs, discussion syntheses, evidence maturity, and semantic linting.
- [[wiki/syntheses/managed-agents-harness-sandbox-separation]] - Synthesizes the Managed Agents discussion around harness/sandbox separation, tool-call control points, recovery limits, many brains/hands, and when the complexity is worth it.
- [[wiki/syntheses/obsidian-cli-for-wiki-maintenance]] - Practical Obsidian CLI commands for linting links, auditing note structure, and safely refactoring the vault.

## Operational Docs

- [[AGENTS]] - The schema that defines page shapes, workflows, and commit message conventions.
- [[README]] - Repository overview and start-here instructions.
- Git history - Canonical operational history for vault changes.
