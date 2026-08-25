# Self-hosted tool candidates for artemis

Research date: 2026-08-22. Machine: NixOS, Ryzen zen4 (CachyOS BORE-LTO kernel), AMD discrete
GPU (Vulkan + ROCm capable), lots of RAM/NVMe, behind NAT, reachable over NetBird mesh from the
Hetzner fleet and a MacBook. Currently running: llama.cpp behind llama-swap (Vulkan backend, TTL
unload), Steam/gamescope/gamemode/Proton, Sunshine (VAAPI headless streaming), impermanence
(root wiped every boot), Hyprland.

Scoring is 1-5 usefulness for this owner: DevSecOps engineer, Rust/Zig/Go/TS background, runs a
personal Telegram LLM agent ("Hermes") he wants to extend with tool-callable backends over the
mesh. "nixpkgs" column is verified where noted, otherwise flagged as unverified.

---

## 1. Local inference stack

**Bottom line: keep llama.cpp + llama-swap.** Nothing unseated it for a single RDNA3/4 desktop
GPU in 2026. The competing "real" serving stacks (vLLM, SGLang) exist mainly to batch many
concurrent users across data-center GPUs; they don't buy a single-user desktop box much, and on
AMD consumer cards Vulkan is still winning benchmarks against ROCm/HIP outright.

| Tool | Repo | What it is | AMD reality | nixpkgs/module | VRAM/RAM | Score |
|---|---|---|---|---|---|---|
| llama.cpp + llama-swap | ggml-org/llama.cpp, mostlygeek/llama-swap | GGUF inference server + hot-swap proxy, already in use | Vulkan backend is the fastest path on RDNA4 today: one RX 9070 XT benchmark showed llama-server/Vulkan at 62 t/s vs vLLM/ROCm at 48 t/s, and a separate test found Vulkan ~23% faster than ROCm/HIP on token generation (220 vs 179 t/s) because RDNA4 kernel support in ROCm-backed stacks is still catching up | `services.llama-swap` NixOS module exists and is what's deployed | current setup, model-dependent | 5 (no change) |
| vLLM (ROCm) | vllm-project/vllm | High-throughput batched serving, PagedAttention | ROCm is now a "first-class" vLLM platform: prebuilt `vllm==0.14.0+rocm700` wheel shipped Jan 2026, AMD CI pass rate 37%→93% Jan 2026. Officially supports RX 7900 XTX/XT (RDNA3) and RX 9070/9070 XT (RDNA4). But RDNA4 FP8 kernels are still not fully merged — loading an FP8 model can silently fall back to slow FP32/FP16 dequant, and it lost the head-to-head above | `lemonade-sdk/vllm-rocm` gives portable ROCm builds; no first-party nixpkgs package found (unverified beyond that) | much higher baseline VRAM than llama.cpp for the same model due to PagedAttention block allocation | 2 — only worth it if you need real multi-user concurrent batching, which a single-desktop-owner setup doesn't |
| SGLang | sgl-project/sglang | Structured-output-focused serving, RadixAttention | ROCm support exists upstream but is behind CUDA in polish; no consumer-RDNA benchmarks turned up for 2026 | not found in nixpkgs | similar to vLLM | 1 |
| Ollama | ollama/ollama | llama.cpp wrapper w/ its own model format/registry | Still just a llama.cpp shim; ROCm/Vulkan support tracks llama.cpp's | `services.ollama` exists in nixpkgs | same as underlying llama.cpp | 1 — llama-swap already gives you hot-swap + OpenAI API without Ollama's extra model-format layer |
| LocalAI | mudler/LocalAI | Multi-backend (llama.cpp, whisper.cpp, piper, stable-diffusion) unified OpenAI-compatible gateway | Backend-dependent; bundles whisper.cpp and go-piper, both of which have Vulkan/ROCm paths | packaged in nixpkgs (referenced as an ecosystem integration point in nixpkgs AI docs) | varies per backend | 3 — interesting as a single front door for STT/TTS/LLM if you want one API surface instead of separate services, but adds an abstraction layer over things llama-swap/whisper.cpp already do directly |
| TabbyAPI + ExLlamaV2/V3 | theroyallab/tabbyAPI, turboderp-org/exllamav2/v3 | Fast exl2/exl3-quant serving | ExLlamaV2 has some ROCm support; **ExLlamaV3 explicitly has no AMD ROCm support as of 2026** (confirmed on the project's own tracker) | not in nixpkgs | n/a | 1 — dead end on this hardware |

**Speculative decoding / KV cache quantization (still on llama.cpp):**
- Speculative decoding (draft model + verification) is mainstream now — llama.cpp supports classic
  draft-model spec decoding and n-gram speculation; some 2026 models (e.g. Qwen3.6) ship native
  multi-token-prediction (MTP) heads that make spec decoding nearly free. Worth trying with a small
  draft model paired against ornith-1.0-9b/qwen3.5-9b if request latency ever matters — llama-swap's
  config already supports per-model extra flags for `--draft-model` cleanly.
- KV cache quantization: llama.cpp has had `--cache-type-k/v q4_0/q8_0` for a while; a newer
  compression scheme called **TurboQuant** (Zandieh et al., ICLR 2026, 3.8-4.9x compression vs FP16)
  has a working implementation under discussion in `ggml-org/llama.cpp#20969` but is not yet merged
  mainline as of this research date — worth revisiting in a few months, not urgent to chase now given
  the 24k-98k token context budgets already configured are comfortable on this card's VRAM.
- Batching: llama.cpp's continuous batching (`-np` parallel slots, already used: 4 slots on
  ornith) is mature and is what the current config already exploits.

---

## 2. Services worth exposing to the fleet over the mesh

All of these would sit behind the same netbird-trusted-interface pattern as llama-swap
(`openFirewall = false`, reachable only via the mesh) so Hermes on legion-node3 can call them as
tool backends.

| Tool | Repo | What it does | AMD reality | nixpkgs/module | VRAM/RAM | Score |
|---|---|---|---|---|---|---|
| whisper.cpp (server mode) | ggml-org/whisper.cpp | STT, OpenAI-compatible `/v1/audio/transcriptions` server mode | Native Vulkan backend (`ggml-vulkan`) works well; ROCm backend also exists via `lemonade-sdk/whisper.cpp-rocm` nightly HIP builds; 1.8.3 claims a 12x boost on integrated AMD/Intel graphics specifically | `whisper-cpp` is packaged in nixpkgs (Vulkan support depends on how it's built — verify flags at build time) | ~1-3 GB depending on model size (base/small/medium) | 5 — cheap, directly useful for a Telegram agent doing voice-note transcription |
| faster-whisper / WhisperX | SYSTRAN/faster-whisper | STT via CTranslate2 | **CTranslate2 does not officially support ROCm** — this is the one to skip on AMD; whisper.cpp is the correct substitute here | packaged in nixpkgs (`python3Packages.faster-whisper`) but GPU path is CUDA-only in practice | n/a | 1 — redundant with whisper.cpp and worse AMD story |
| Piper (TTS) | rhasspy/piper | Fast, small neural TTS, many languages, ONNX-based | CPU-first by design; runs fine without GPU, which is a feature here (frees the card for LLM work) | `piper-tts` is packaged in nixpkgs | <1 GB RAM, no GPU needed | 4 |
| Kokoro (TTS) | hexgrad/Kokoro-82M | 82M-param TTS, praised as beating much bigger models in blind tests | GPU-accelerated builds documented are CUDA-first (see `hwdsl2/docker-kokoro`); should run via ONNX/CPU reasonably given its small size but no confirmed AMD GPU path found in this research pass | not found in nixpkgs as of this search | ~4 GB VRAM if GPU-accelerated, otherwise CPU-viable given 82M params | 3 — better voice quality than Piper if you're willing to run it CPU-only or chase an AMD ONNX path yourself |
| ComfyUI | comfyanonymous/ComfyUI | Node-based image-gen (SD/SDXL/Flux) workflow engine | Real 2026 news: AMD ROCm support landed officially for ComfyUI Desktop (Windows, Jan 2026) and ROCm 7.1.1-7.2 posts up to 5.4x uplift on RDNA-class hardware; Linux path is "install ROCm 7.2, run ComfyUI" without the old environment-variable workarounds | not found packaged in nixpkgs directly (commonly run via its own venv/Docker); confirm before relying on a Nix-native path | 8-16+ GB VRAM depending on model/resolution | 4 — genuinely useful idle-GPU workload, but expect to run it outside the Nix store (venv or container) rather than as a clean module |
| SD.next / Forge | vladmandic/sdnext, Automatic1111 forks | Alternative SD web UIs | Same ROCm story as ComfyUI, generally a notch behind on RDNA4 driver support | not in nixpkgs | similar to ComfyUI | 2 — ComfyUI is the better-supported pick, no reason to run both |
| text-embeddings-inference (TEI) | huggingface/text-embeddings-inference | Fast embeddings/reranker server, OpenAI-compatible-ish API | HF's TEI has CUDA-first Docker images; CPU backend works everywhere but GPU acceleration on AMD is not first-class — llama.cpp's own `--embedding` server mode (already in your llama-server binary) is the safer AMD path for embeddings | not found packaged in nixpkgs | small (<1 GB for typical embedding models) | 3 — use llama-server's embedding mode instead of standing up TEI separately |
| Qdrant | qdrant/qdrant | Vector database, Rust, single static binary | CPU-only workload, no GPU dependency at all — a non-issue here | **`services.qdrant` is a real NixOS module** (verified: enable/package/settings/webUIPackage options exist) | light, scales with corpus size | 5 — Rust-native, trivial NixOS module, exactly the kind of infra a Rust dev extending a personal agent wants for RAG/memory |
| Surya OCR | VikParuchuri/surya | Multilingual OCR + layout/document understanding, SOTA accuracy | GPU accelerates it but it runs on CPU too; recommended minimum is ~4 GB VRAM for GPU mode — trivial for this card. No explicit AMD/ROCm confirmation found; likely PyTorch+CUDA by default, worth testing CPU fallback first | not found in nixpkgs | ~4 GB VRAM (GPU) or CPU-only | 3 |
| mem0 | mem0ai/mem0 | Agent long-term memory (vector store + optional knowledge graph) | Pure Python/API service, no GPU needed; self-host Docker guide pairs it with Qdrant already on the list | not found in nixpkgs (pip/Docker install) | light | 4 — directly on-theme for "extend Hermes with tool-callable backends"; pairs naturally with the Qdrant instance above |
| Zep / Graphiti | getzep/graphiti | Temporal knowledge-graph agent memory | Graphiti (the open-source engine) stays open source, but Zep retired its self-hosted Community Edition in 2026 — the packaged product path is now hosted-only | n/a | heavier (needs a graph DB) | 2 — more operational weight than mem0 for a personal-scale agent, skip unless you specifically need "what was true and when" temporal queries |

---

## 3. Local AI apps

| Tool | Repo | What it does | AMD reality | nixpkgs/module | Score |
|---|---|---|---|---|---|
| Open WebUI | open-webui/open-webui | Chat UI, OpenAI-compatible backend, RAG, tools | No GPU dependency itself (just talks to llama-swap's endpoint) | **`services.open-webui` is a real NixOS module** (verified: enable/environment/environmentFile/host/openFirewall/package/port/stateDir options) | 4 — still the default choice; low effort since the module already exists, gives a web front end to the models you're already running |
| LibreChat | danny-avila/LibreChat | Multi-provider chat UI, MCP support, code interpreter | Same, no GPU dependency | not found in nixpkgs | 2 — nicer UX in some reviews but Open WebUI's existing NixOS module is the lower-friction pick |
| SearXNG | searxng/searxng | Meta search engine, good LLM-tool-use search backend | No GPU | **`services.searx` NixOS module exists** (nixpkgs wiki page confirms) | 4 — a private search backend Hermes could call as a tool is directly useful and the module already exists |
| Wyoming protocol / Home Assistant Voice | home-assistant/wyoming, various satellites | Standard protocol wiring STT/TTS/wake-word into Home Assistant's Assist pipeline | Community reports mixed AMD ROCm+onnxruntime results (openSUSE forum thread found no clean answer); most published 2026 recipes assume NVIDIA | wyoming-piper etc. exist as smaller community packages, not confirmed in nixpkgs directly | 2 — only relevant if you actually run Home Assistant; not mentioned as part of this host's stack, so treat as a "someday" item, not a near-term pick |
| Lightweight RAG (llama.cpp embeddings + Qdrant + a thin script) | — | Roll-your-own RAG instead of a framework | N/A — this is the "actually light" option the research explicitly asked about; frameworks like LangChain were consistently described as heavier than needed for a personal setup | components above are already nixpkgs-native | 4 — given the Rust/Go/TS background, wiring llama-server's embedding endpoint + Qdrant directly (skip LangChain-style frameworks) is both idiomatic and avoids a dependency swamp |

---

## 4. Media / transcode / GPU workloads

| Tool | What it does | AMD reality | Score |
|---|---|---|---|
| Jellyfin hardware transcode (VAAPI) | Transcode over the mesh for remote fleet clients | VAAPI on AMD dGPU (RX 6000/7000-class VCN encoder) works and HDR tone-mapping via OpenCL is supported; documented as "less polished than Intel/NVIDIA docs but functional" in 2026 write-ups. artemis already has the render-node-by-path pattern solved for Sunshine's VAAPI encoder (`modules/nixos/sunshine.nix`), which is directly reusable for Jellyfin's `/dev/dri` access | 3 — only relevant if Jellyfin isn't already running elsewhere in the fleet; if it is, offloading transcode to artemis over the mesh is a reasonable idle-GPU use, reusing the by-path render-node trick already proven in `sunshine.nix` |
| Immich ML remote offload | Photo CLIP search / face recognition, offloaded from a lighter fleet node | Immich's ML container explicitly supports a `rocm` backend and **remote machine-learning offload is a first-class Immich feature** (point another Immich instance's ML settings at this box's URL) — confirmed via Immich's own docs. Caveat: the ROCm Docker image needs ~35 GiB free disk and DKMS/secure-boot key enrollment for the amdgpu module | 4 — a clean fit: point the fleet's Immich instance at artemis's ML endpoint over the mesh, keep the heavy CLIP/face models off the always-on Hetzner nodes |
| Video2X / frame interpolation | Upscaling/interpolation | GPU-accelerated, Vulkan-capable builds exist (Video2X ships a Vulkan-based waifu2x-ncnn path already tolerant of non-NVIDIA GPUs) | 2 — niche, only if you actually do video upscaling work; not central to the DevSecOps/agent use case |

---

## 5. Gaming / streaming

**Sunshine is being overtaken by Apollo for anyone who cares about virtual-display / per-client
resolution matching, but it's not a slam-dunk swap.**

| Tool | Repo | What it does | Notes | Score |
|---|---|---|---|---|
| Sunshine (current) | LizardByte/Sunshine | Headless Moonlight-compatible streaming host | Already deployed, VAAPI encoder pinned by render-node path, works. Stable, well-documented, has a NixOS module already in use | 4 (status quo is fine) |
| Apollo | ClassicOldSong/Apollo | Sunshine fork adding a virtual display (SudoVDA) with automatic per-client resolution/refresh-rate matching, no physical-output juggling | Directly solves the exact problem your current `sunshine-stream-mode` script hacks around by shelling into `hyprctl eval` to switch physical-monitor modes per client — Apollo's virtual display makes that whole prep-cmd unnecessary. Actively maintained through 2025-2026, drop-in for existing Moonlight clients. Not found packaged for NixOS (nixpkgs ships `sunshine`, not `apollo`) — would need a custom derivation or an overlay | 4 — worth a real evaluation given it removes a maintenance burden (the whole `resolutionPrep`/`hyprctl eval` hack in `sunshine.nix`), but the missing nixpkgs packaging is real integration work, not a drop-in config change |
| "Artemis" (Apollo companion) | — | Automates Apollo's client-side features | **This is an unrelated third-party Android app that happens to share your hostname** — not to be confused with your machine. Not relevant here beyond the naming coincidence; flagging so it isn't mistaken for a recommendation | n/a |
| Duo | fork of Sunshine | Multi-device cloud-streaming-oriented fork | Less directly relevant — aimed at multi-seat cloud gaming providers, not a single-user home setup | 1 |

---

## 6. Genuinely novel / worth a look

- **MTP-native models (e.g. Qwen3.6-class) + TurboQuant KV compression** — described in current
  discussion as the "2026 sovereign inference triple-stack" (weight quant + spec decoding + KV
  compression). Not yet mainline in llama.cpp but worth tracking; would materially cut VRAM
  pressure on long-context sessions once merged.
- **Rust-native local-AI infra generally** — Qdrant (vector DB) and llama.cpp/llama-swap (Go) are
  both already good fits for a Rust/Go-leaning owner; the honest 2026 finding is that the exciting
  new tooling (vLLM, SGLang, ExLlamaV3) is chasing multi-tenant cloud-GPU throughput, which is not
  this machine's problem. The interesting frontier for a single idle desktop GPU is smaller and more
  boring: better quantization, cheap speculative decoding, and using the GPU for photo ML / image
  gen / transcode when it isn't serving tokens — not a new serving framework.
- **Immich remote ML offload** (see section 4) is the most concretely "new to consider" idea that
  fell out of this research: it's a real, documented, first-class feature, matches this exact
  topology (idle desktop GPU + lighter always-on fleet nodes), and nothing else in this list is as
  clean a fit for the existing fleet architecture.

---

## Final ranked shortlist (top 5)

1. **Qdrant** (`services.qdrant`, verified NixOS module) — Rust-native vector DB, zero GPU
    dependency, the natural RAG/memory backend for Hermes. Lowest integration cost on this list.
2. **whisper.cpp server mode** — cheap, Vulkan-accelerated STT endpoint over the mesh; turns
    Telegram voice notes into a Hermes tool call almost for free given the model is already on
    this box's toolchain.
3. **Immich ML remote offload** — first-class documented feature, exactly matches the
    idle-desktop-GPU / lighter-fleet-node topology already in place.
4. **Apollo (Sunshine fork)** — removes the `hyprctl eval` per-client resolution hack currently
    carried in `modules/nixos/sunshine.nix`, at the cost of packaging it yourself (no nixpkgs
    package found).
5. **mem0 + Qdrant** — agent long-term memory, self-hosts in about 20 minutes per its own docs,
    directly extends the Telegram agent's capability set the way the prompt asked for.

**No change recommended to the core inference stack.** llama.cpp + llama-swap on Vulkan remains
the right call for this specific GPU class in 2026 — vLLM/SGLang/TabbyAPI-ExLlamaV3 either lose
head-to-head benchmarks on RDNA4 today, have no AMD support at all (ExLlamaV3), or exist to solve
a multi-tenant throughput problem this single-user box doesn't have.
