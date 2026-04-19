# Omni 🌸

### Give everything a soul.

> *Everything has a voice — choose what it teaches you.*

Hey, you! 👋 Welcome to **Omni**, a joyful little open-source experiment that turns the world around you into a cast of chatty, cartoon-faced characters. Point your phone at a mug, a houseplant, a half-eaten sandwich, or your very judgemental office chair — tap it — and *boom*, it wakes up with eyes, a mouth, a personality, and a voice of its own. Then you can talk back. 🎙️✨

It's silly. It's warm. It's the kind of magic we wanted to exist, so we built it. We hope you love hacking on it as much as we loved making it.

---

## ✨ What's inside

Omni is actually **two tiny apps** sharing one cozy codebase:

### 🎯 Tracker *(the main one, at `/`)*
Your camera becomes a world full of characters.
- **On-device object detection** with YOLO26n-seg running right in your browser (WebGPU → WASM). No server round-trip for the vision loop. 🧠
- **Tap to bring things to life.** A cartoon face (`FaceVoice`) latches onto the object and follows it around — pinned perfectly using mask-centroid anchors, even as the object moves, shrinks, or hides behind things. 🪄
- **Unique personas per object.** A bundled `gpt-4o-mini` vision call writes the opening line, picks a Fish.audio voice from our 9-voice catalogue (EGirl, Elon, Anime Girl, Peter Griffin, Sonic, an Elephant 🐘, and friends), and captures a persona card. Every follow-up riff and conversation runs off that card via Cerebras Llama — so the character stays *consistent*, and replies land in ~200ms.
- **Talk back!** Hit the mic, say something, and your cup/lamp/dog-toy responds in character, in its own voice, streaming straight back to you.
- **Up to 3 objects talking at once** — because why not. 🗣️🗣️🗣️

### 🪞 Mirror *(at `/mirror`)*
The original experiment. Your webcam streams to a local Python server which uses dlib + OpenCV `seamlessClone` to paste your real eyes and mouth onto a base image (an orange, a pumpkin, whatever you upload). You become the thing. It's weird and wonderful. 🍊👀

---

## 🧁 The vibe

Pink. Pastel. Bubbly. Blob-floaty. Intentionally joyful.
If you see `animate-blob-float`, `soft-pulse`, `wiggle-on-hover`, or a pastel radial background — that's the house style, not cruft. Keep it sparkly. ✨

---

## 🚀 Quick start

Requires **Node ≥ 20** and **pnpm** (we ❤️ pnpm).

```bash
pnpm install          # also fetches ONNX runtime WASM into public/ort
pnpm dev              # https://localhost:3000  (self-signed cert so camera works)
```

That's it for Tracker! Open `/` on your phone, allow camera, and start tapping things.

### Environment variables

Create a `.env.local` at the repo root:

```bash
# Required for Tracker
OPENAI_API_KEY=sk-...         # bundled first-tap line + persona card + STT fallback
ZHIPU_API_KEY=...             # GLM glm-5v-turbo — face-placement / object assessment

# Strongly recommended (makes retaps + conversation ~5x faster)
CEREBRAS_API_KEY=...          # llama3.1-8b text-only on the hot path

# TTS (at least one of these — otherwise you get caption-only mode)
FISH_API_KEY=...              # primary character voices
# (falls back to OpenAI tts-1/nova automatically if Fish is missing)
```

### Running Mirror too?

```bash
# one-time Python setup
python3 -m venv server/.venv
server/.venv/bin/pip install opencv-python dlib imutils numpy openai \
  fastapi "uvicorn[standard]" python-multipart websockets python-dotenv

# download dlib's 68-landmark model into server/ (see CLAUDE.md for URL)

pnpm server           # FastAPI + WebSocket on :8000
# or run both apps together:
pnpm demo
```

---

## 🧩 Tech stack

- **Frontend** — Next.js 15 (App Router), React 19, TypeScript, Tailwind v4
- **On-device vision** — `onnxruntime-web` running YOLO26n-seg (~9.4 MB, shipped in `public/models/`)
- **LLMs** — OpenAI `gpt-4o-mini` (vision + fallback), Cerebras `llama3.1-8b` (hot path), GLM `glm-5v-turbo` (placement)
- **Voices** — Fish.audio streaming TTS with OpenAI `tts-1/nova` fallback, streamed via `MediaSource` for sub-second TTFB
- **Mirror backend** — Python 3.12, FastAPI, OpenCV, dlib

---

## 📂 Where things live

```
app/                      Next.js routes (/, /mirror, /landing)
  actions.ts              Server actions — assess / describe / generateLine / converseWithObject
  api/tts/stream/         Streaming TTS passthrough (Fish → browser, chunked)
components/
  tracker.tsx             The Tracker UI + tracking loop (the big one)
  face-voice.tsx          The cartoon-face renderer (eyes video + 9 mouth shapes)
  mirror.tsx              The Mirror UI
lib/
  yolo.ts                 Browser object detector
  iou.ts                  IoU matching, EMA smoothing, anchor math
server/                   Mirror's FastAPI backend (optional)
public/
  models/yolo26n-seg.onnx The detector weights
  facevoice/              Eyes video + mouth-shape PNGs
```

Deeper architecture notes, prompt design, and load-bearing constants live in [`CLAUDE.md`](./CLAUDE.md) — highly recommended reading if you're about to hack on the tracker loop.

---

## 🛠 Scripts

| Command | What it does |
|---|---|
| `pnpm dev` | Run Next.js with HTTPS on :3000 |
| `pnpm build` / `pnpm start` | Production build & serve |
| `pnpm typecheck` | `tsc --noEmit` — the only automated gate |
| `pnpm server` | Run the Python server for Mirror |
| `pnpm demo` | Run Next + Python together |

No lint script, no test framework — just vibes and types. 💅

---

## 🤝 Contributing

We'd absolutely love your help! Whether it's a new voice in the catalogue, a bug fix in the tracking loop, a new base image for Mirror, or just a typo — **please open a PR**. There are no silly ideas here.

A few gentle guidelines:
- Keep the pink/pastel bubbly aesthetic unless there's a reason not to. 🌸
- Prefer editing existing files over creating new ones.
- Run `pnpm typecheck` before pushing.
- If you touch the tracking loop, read the "Things to know" section of `CLAUDE.md` first — there are a few load-bearing constants and guards that look innocent but really aren't.

Stuck? Confused? Curious? **Open an issue** and say hi. We answer every one. 💌

---

## 🌈 A note from us

Omni started as a hackathon toy and grew into something we genuinely adore. The world is full of objects we walk past without noticing — and giving them a voice, even a silly one, changes how you see a room. We hope it does the same for you.

Go tap something. See what it has to say. ✨

---

**License:** MIT — do whatever brings you joy.

Made with 🫧 and too much espresso.
