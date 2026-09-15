# Third-Party Notices

## Stable Audio Open Small

- Model: `stabilityai/stable-audio-open-small`
- Source: <https://huggingface.co/stabilityai/stable-audio-open-small>
- Publisher: Stability AI
- License: Stability AI Community License, supplied in the model repository
- License text: <https://huggingface.co/stabilityai/stable-audio-open-small/blob/main/LICENSE>

The model weights are not included in this repository and are not licensed under this repository's MIT license. Each user must review and accept the applicable Stability AI terms themselves before downloading or using the model. Commercial eligibility depends on the current license terms and the user's circumstances; this project makes no broader licensing representation.

Stable Audio Open Small's published configuration uses the separately downloaded `t5-base` text encoder from Google/Hugging Face. Its upstream model card and included license files remain authoritative.

## Stable Audio Tools

- Source: <https://github.com/Stability-AI/stable-audio-tools>
- Package: `stable-audio-tools==0.0.20`
- License: MIT as stated by the upstream repository

The Python environment also installs Stable Audio Tools dependencies declared by that package. Their respective package metadata and license files remain authoritative.

The V0 runtime pins NumPy 1.26.4 because Stable Audio Tools 0.0.20 requires PyWavelets 1.4.1, whose macOS wheel is not ABI-compatible with NumPy 2.x. It also installs the upstream-pinned PyTorch Lightning 2.5.5 because Stable Audio Tools imports its LoRA callbacks while constructing this inference model.

## JUCE

- Source: <https://github.com/juce-framework/JUCE>
- Version: 8.0.12
- Pinned commit: `29396c22c93392d6738e021b83196283d6e4d850`
- License: dual-licensed under AGPLv3 and the commercial JUCE 8 licence

JUCE is fetched into an ignored tooling directory and is not vendored into this repository. This repository's MIT license does not override JUCE's terms: distributing a non-AGPL/closed-source build requires an appropriate JUCE commercial licence. The VST3 SDK included by this pinned JUCE checkout is identified in JUCE's own notice as MIT-licensed; the upstream checkout remains authoritative for all transitive notices.
