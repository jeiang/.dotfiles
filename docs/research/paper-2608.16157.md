# FreeToken: Efficient Edge-Native MoE Serving with Bandwidth-Adaptive Execution

- **arXiv ID:** 2608.16157
- **Title:** FreeToken: Efficient Edge-Native MoE Serving with Bandwidth-Adaptive Execution
- **Authors:** Shuo Yang, Xiaoze Fan, Melissa Pan, Haocheng Xi, Zhe Wang, Shanlin Sun, Kurt Keutzer, Song Han, Matei Zaharia, Chenfeng Xu, Ion Stoica
- **Affiliation:** UC Berkeley and UT Austin (inferred from correspondence emails `andy_yang@berkeley.edu`, `xuchenfeng@utexas.edu`; the abstract page itself does not list affiliations)
- **Submitted:** August 17, 2026, v1
- **Category:** cs.DC (Distributed, Parallel, and Cluster Computing)
- **Links checked:** abstract page (arxiv.org/abs/2608.16157), HTML full text (arxiv.org/html/2608.16157), PDF, and the linked code repo (github.com/FlashML-org/FreeToken) — all resolved and were fetched.

No text in the paper was addressed to an AI agent or contained embedded instructions; nothing to flag there.

## What it actually claims

FreeToken is a serving system for Mixture-of-Experts (MoE) LLMs on a single consumer/workstation machine, where the full expert set doesn't fit in GPU VRAM. It treats the machine as a unified GPU+CPU+PCIe pipeline rather than a small GPU with an offload fallback bolted on. Three problems it targets: prefill overhead from expert transfer, decode-time cache misses on missing experts, and variable per-machine hardware bandwidth.

**Core mechanism — bandwidth-adaptive execution.** On a cache miss for `m` experts, instead of always streaming them over PCIe into VRAM (transfer-bound) or always running them on CPU (compute-bound), FreeToken computes a split point `q* ≈ m·B_P/B_H` (PCIe transfer bandwidth vs. host expert-execution bandwidth, both empirically measured per machine, not read from spec sheets) and runs the two subsets concurrently — `q*` experts fetched to GPU cache slots, the rest executed in place from the CPU-resident expert pool. This is the paper's one real algorithmic idea; everything else is systems engineering around it.

**Supporting pieces:**
- Double-buffered prefill: while GPU computes layer `l`'s experts, a separate stream loads layer `l+1`'s full expert set.
- Global LRU expert cache (device-side, single-pass eviction kernel) instead of static/workload-agnostic expert pinning (what llama.cpp and KTransformers do).
- "Semantic-aware" KV/state checkpointing keyed to special-token boundaries (tool calls, turn boundaries) so agentic multi-turn workloads don't repeatedly pay full prefill cost.
- A custom on-disk weight format (FTW) that pre-merges experts into the runtime layout to skip load-time repacking.
- Native MXFP4/NVFP4 quantized-expert support alongside BF16.

## Results and their limits

Tested on Qwen3.6-35B-A3B, DeepSeek-V4-Flash (284B/13B active), and GLM-5.2 (753B/40B active, 433GB checkpoint), against llama.cpp, Ollama, KTransformers, and MoE-Infinity, across four workloads (math reasoning, two coding-agent variants, an email/calendar agent).

Reported: 1.8–2.3x decode throughput over baselines depending on model/workload; TTFT held under 44s worst-case vs. baselines exceeding 150s (llama.cpp 232s, Ollama 179s, KTransformers 946s in the worst cell); decode rate stays within 12% of single-turn baseline across agentic workloads vs. KTransformers losing 31%; cache-miss rate 16–39% vs. 41–59% (KTransformers) and 62–89% (llama.cpp static split); disabling double-buffering costs 19–26% throughput.

**What's not shown:**
- All six evaluated machines are NVIDIA-only (RTX 3090/4090/5090, RTX PRO 6000, RTX 4060 laptop). No AMD/ROCm hardware appears anywhere in the evaluation.
- Baseline comparisons are against generalist offload tools (llama.cpp, Ollama, KTransformers) that were not necessarily tuned for these specific bandwidth ratios — the paper doesn't report what tuning effort, if any, went into the baselines, which is the usual "baseline may be underexploited" concern in a paper introducing its own tuned parameter (`q*`).
- No comparison against a datacenter/multi-GPU tensor-parallel serving setup, so the paper can't claim FreeToken closes the gap to real cluster serving — it only claims to beat other single-machine offload tools.
- No power/energy numbers, no sustained-load (many concurrent users) test — everything is single-stream single-user latency/throughput.
- Ablations are limited to two (double-buffering, cache locality); no ablation isolating the `q*` formula itself against simpler heuristics (e.g., static 50/50 split, or always-GPU/always-CPU) — so it's not demonstrated that the bandwidth-adaptive formula specifically, versus just having *some* GPU/CPU concurrency, drives the gain.

## Code, weights, license — verified

Repo exists: `github.com/FlashML-org/FreeToken`, Apache 2.0 licensed. README states "native support for NVIDIA RTX 30, RTX 40, and RTX 50 series GPUs" — explicitly NVIDIA-only, no AMD/ROCm/HIP mentioned anywhere. Install is `uv pip install "freetoken[accel]"` or a prebuilt desktop app for Windows/Linux via flashml.ai. No pretrained weights are shipped (you bring your own MoE checkpoint in MXFP4/NVFP4/BF16); the FTW conversion step repacks a downloaded checkpoint into their runtime format.

## Reproducibility and hardware dependency

This is the part that matters most for this reader. FreeToken depends on:
- CUDA Graphs for its device-side cache-control kernel (dedup routed experts, classify residency, compute `q*`, select LRU eviction victims — described as one fused GPU kernel).
- `cudaHostRegister`/pinned-memory DMA transfers between host and device (the whole `B_P` bandwidth term is a PCIe DMA measurement).
- NVFP4/MXFP4 quantization formats, which are NVIDIA-specific numeric formats (MXFP4 has broader hardware support conceptually, but the kernels here are CUDA).

None of this has a documented HIP/ROCm path. This is a CUDA-only system, not "GPU-agnostic MoE offloading" — the bandwidth-adaptive *idea* is portable, the implementation is not.

## Relevance to this reader's setup

**Practical applicability: 1/5** — interesting, not usable as-is.

The Ryzen 4/AMD GPU desktop running llama.cpp/llama-swap is exactly the offload scenario FreeToken targets (MoE model too big for VRAM, CPU+GPU split), and the `q*` bandwidth-split concept is a genuinely useful idea to know about even outside this codebase. But the shipped software is NVIDIA-only end to end (CUDA Graphs, DMA kernels, NVFP4/MXFP4 tuned to NVIDIA tensor cores), Apache 2.0 license notwithstanding — there's nothing to `pip install` and run on the AMD box. Porting the `q*` heuristic into llama.cpp's existing CPU/GPU split logic is conceivable as a future llama.cpp PR (their `--n-cpu-moe`/offload logic is a coarser static split today), but that's a from-scratch reimplementation, not adopting this project. On the Hetzner NixOS fleet (1.9GiB RAM/node) it's irrelevant — those nodes have no GPU and nowhere near enough RAM to host a CPU-resident expert pool for any of the models tested (35B–753B). No relevance to Hermes' Telegram/git-KB architecture either — this is a low-level inference-serving paper, not an agent-orchestration one.

## 15-line summary

FreeToken (arXiv:2608.16157, UC Berkeley/UT Austin, Aug 17 2026, cs.DC) is an edge-native MoE LLM serving system for single machines where the full expert set exceeds VRAM. Its core idea: on each decode-step cache miss of `m` experts, split them into a PCIe-transfer-to-GPU subset and a CPU-execute-in-place subset, sized by measured host/PCIe bandwidth ratio (`q* ≈ m·B_P/B_H`), running both concurrently instead of choosing one strategy statically. Supporting features: double-buffered prefill, global LRU expert cache with a fused single-pass eviction kernel, semantic-boundary state checkpointing for agentic multi-turn workloads, and a custom pre-packed weight format (FTW). Tested on Qwen3.6-35B, DeepSeek-V4-Flash (284B/13B active), and GLM-5.2 (753B/40B active) across six NVIDIA-only machines (RTX 3090 up to RTX PRO 6000, plus a laptop 4060), against llama.cpp, Ollama, KTransformers, and MoE-Infinity. Reports 1.8-2.3x decode throughput and much lower worst-case TTFT (44s vs 150s+) than baselines, plus lower expert-cache-miss rates. Evaluation gaps: no AMD/non-NVIDIA hardware, no datacenter/multi-GPU baseline, no power numbers, no multi-user concurrent load test, and the `q*` formula itself isn't ablated against a naive static split, so its specific contribution beyond "add GPU/CPU concurrency" isn't isolated. Code and a desktop app are released at github.com/FlashML-org/FreeToken under Apache 2.0, no bundled weights. Verified: the whole stack (CUDA Graphs, pinned-memory DMA, NVFP4/MXFP4 kernels) is CUDA-only with no ROCm/HIP path — despite the permissive license, it will not run on an AMD GPU. Relevant conceptually to a CPU/GPU llama.cpp offload setup on Zen4+AMD hardware, but not directly usable there; not applicable to a RAM-constrained ARM/x86 Hetzner fleet or to the Hermes agent. Practical applicability: 1/5 — worth knowing the idea exists, nothing here to run or adopt today.
