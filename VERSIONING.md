# Versioning

This document explains, in simple terms, how I currently think about updates and release labels for this repository.

This is a personal hobby project, it is heavily AI-assisted, and it is also a learning experience for me. I am figuring things out as I go, so I do not want this document to sound more polished, official, or confident than the project really is.

Security is a major concern of mine, and I try to make choices that are as safe and thoughtful as I can with my current knowledge. At the same time, I am not a security expert and I am not a programmer, so mistakes, weak assumptions, and blind spots are all possible.

If you notice something I could do better, I am open to constructive criticism, feedback, and recommendations.

---

## Update approach

At a high level, this repository follows upstream [Forge Neo](https://github.com/Haoming02/sd-webui-forge-classic/tree/neo) release tags. It does not track Neo's daily commits between releases.

In practice, that means:
- a scheduled check opens a pull request when Neo tags a new release, and merging it builds a new `:dev` image
- releases may happen irregularly
- some updates may be small, while others may include larger upstream changes

The image pins the same `torch`, `torchvision` and `gradio` versions that Forge Neo itself installs for that release. That keeps each image reproducible and matched to what upstream tested.

If you choose to use something from this repo, I recommend reviewing changes for yourself and deciding whether a given update fits your own setup, goals, and comfort level.

---

## Tags

The current tagging strategy:

- `:dev`: floating pre-release tag, always points to the latest commit on the `dev` branch. Use this if you want to track development.
- `:vX.Y.Z` (e.g. `:v1.0.0`): pinned version tags for specific tested states. Use these if you want reproducibility.
- `:latest`: stable release tag, promoted from `dev` only after real-world validation. Not yet published.

`main` branch and `:latest` are frozen until `dev` proves stable.

---

## Version labels

I use simple semantic-style version labels:

- `v1.0.0`, `v1.1.0`, `v2.0.0`, etc.

These are not a promise of SemVer compatibility or formal support.
They are just a way to refer to a specific tested state.

---

## Upstream reference

Every image records the Forge Neo release it was built from in its labels (`sd-webui-forge-neo-unraid.upstream.tag` and `.ref`). Up to `v1.x`, this project packaged AUTOMATIC1111 instead.

That is meant to improve clarity. It should not be taken as a guarantee of full reproducibility.

For example, if upstream changes dependency expectations or launcher behavior in a way that affects container startup, I may pin or adjust versions here before considering a release state usable.

---

## What this project does not promise

Things this project does not promise:
- a fixed release schedule
- active validation of every upstream change before publication
- long-term support for older releases
- compatibility with every host, driver, or workflow

I am sharing this because it may be useful to someone else, but anyone using it should validate it for their own environment, threat model, and risk tolerance.

---

## A note on tone and expectations

I want this project to be approachable, personal, and honest.

I also want to be transparent that:
- this project includes a lot of AI-assisted "vibe coding"
- I am learning as I go
- security is something I care deeply about, but I may still get things wrong
- mistakes, weak assumptions, or awkward decisions are possible
- feedback is welcome, especially if it helps me do things in a safer or more thoughtful way

Please do not expect a perfect result here. If this project becomes more structured later, I can expand this document then. For now, I would rather keep it simple, humble, and honest.