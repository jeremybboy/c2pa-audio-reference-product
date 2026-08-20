#!/usr/bin/env python3
"""Stable Audio Open Small helper process for Loop Generator.

The Swift application communicates with this executable boundary through
arguments and generated files. No UI behavior lives here.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import traceback


MODEL_ID = "stabilityai/stable-audio-open-small"
MODEL_DISPLAY_NAME = "Stable Audio Open Small"
EXPECTED_SAMPLE_RATE = 44_100
EXPECTED_CHANNELS = 2


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate a local instrumental loop")
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--seconds", required=True, type=int, choices=(4, 8, 11))
    parser.add_argument("--seed", required=True, type=int)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--metadata-output", required=True, type=Path)
    parser.add_argument(
        "--allow-download",
        action="store_true",
        help="Allow network model fetches during explicit setup only",
    )
    return parser.parse_args()


def cached_model_revision() -> str:
    try:
        from huggingface_hub import scan_cache_dir

        cache = scan_cache_dir()
        for repository in cache.repos:
            if repository.repo_id == MODEL_ID and repository.revisions:
                revision = max(repository.revisions, key=lambda item: item.last_modified)
                return revision.commit_hash
    except Exception:
        pass
    return MODEL_ID


def generate(args: argparse.Namespace) -> None:
    if not args.allow_download:
        os.environ["HF_HUB_OFFLINE"] = "1"
        os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

    import numpy as np
    import soundfile as sf
    import torch
    from stable_audio_tools import get_pretrained_model
    from stable_audio_tools.inference.generation import generate_diffusion_cond

    requested_device = os.environ.get("LOOP_GENERATOR_DEVICE", "auto")
    if requested_device == "auto":
        if torch.cuda.is_available():
            device = "cuda"
        elif torch.backends.mps.is_available():
            device = "mps"
        else:
            device = "cpu"
    else:
        device = requested_device
    print(f"Loading {MODEL_ID} on {device}", flush=True)
    model, model_config = get_pretrained_model(MODEL_ID)
    sample_rate = int(model_config["sample_rate"])
    sample_size = int(model_config["sample_size"])
    if sample_rate != EXPECTED_SAMPLE_RATE:
        raise RuntimeError(f"Unexpected model sample rate: {sample_rate}")

    model = model.to(device)
    model.eval()
    conditioning = [{"prompt": args.prompt, "seconds_total": float(args.seconds)}]

    print("Generating audio", flush=True)
    with torch.inference_mode():
        output = generate_diffusion_cond(
            model,
            steps=8,
            cfg_scale=1.0,
            conditioning=conditioning,
            sample_size=sample_size,
            seed=args.seed,
            sampler_type="pingpong",
            device=device,
        )

    audio = output[0].detach().to(torch.float32).cpu()
    target_frames = args.seconds * sample_rate
    audio = audio[:, :target_frames]
    peak = torch.max(torch.abs(audio)).item()
    if not np.isfinite(peak):
        raise RuntimeError("Model produced non-finite audio")
    if peak > 0:
        audio = audio / peak
    audio = audio.clamp(-1, 1).transpose(0, 1).numpy()
    if audio.ndim != 2 or audio.shape[1] != EXPECTED_CHANNELS:
        raise RuntimeError(f"Unexpected output shape: {audio.shape}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.metadata_output.parent.mkdir(parents=True, exist_ok=True)
    sf.write(args.output, audio, sample_rate, subtype="FLOAT", format="WAV")
    args.metadata_output.write_text(
        json.dumps(
            {
                "modelName": MODEL_DISPLAY_NAME,
                "modelVersion": cached_model_revision(),
                "modelRepository": MODEL_ID,
                "sampleRate": sample_rate,
                "channels": EXPECTED_CHANNELS,
                "durationSeconds": args.seconds,
                "seed": args.seed,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {args.output}", flush=True)


def main() -> int:
    args = parse_args()
    try:
        generate(args)
    except Exception as error:
        traceback.print_exc()
        print(f"Stable Audio inference failed: {error}", file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
