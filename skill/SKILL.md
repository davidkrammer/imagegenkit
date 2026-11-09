---
name: imagegenkit
description: Generate or edit images with the local `imagegenkit` command (ImageGenKit). Use it whenever the user asks to create, generate, render, mock up or edit an image, or a task needs a raster image asset (photos, product shots, thumbnails, mockups, icons, illustrations, backgrounds, app/store assets, transparent PNGs, restyles, combining reference images).
metadata:
  managed-by: ImageGenKit
  version: 1.0.0
---

# Images with `imagegenkit`

`imagegenkit` is installed at `~/.local/bin/imagegenkit` by the ImageGenKit app. Providers, keys, defaults and which provider handles which task are the user's settings in ImageGenKit. Don't hardcode a provider unless the user names one.

## Pick the task

```bash
imagegenkit draft "PROMPT" -o out.jpg          # quick mockups, ideas, drafts (cheapest)
imagegenkit final "PROMPT" -o out.png          # final designs and final-level mockups
imagegenkit edit "PROMPT" -i in.png -o out.png # edit or refine an image (repeat -i to combine)
imagegenkit transparent "PROMPT" -o out.png    # transparent PNG: logo, sticker, cut-out
```

Common options: `--aspect 16:9`, `-n 2`, `-i ref.png`, `-f prompt.txt`, `--dry-run`. Run `imagegenkit <task> -h` for more.
Only if the user asks for a specific provider: `imagegenkit openai|grok|xai|gemini|<custom> "PROMPT"` or `imagegenkit draft -p openai ...`.

## Rules

- **Start of a session:** run `imagegenkit providers` once. If nothing is ready, ask the user to open ImageGenKit › Settings › Providers. **Never ask for API keys in chat, never print them, never write them to files.**
- **Lowest cost that fits.** Ideas and drafts use `draft`. Use `final` only for finished work. Use `-n 1`, and ask before making more than about 6 paid images at once.
- **Turning a draft into a final:** pass the draft with `-i` to `edit` or `final`.
- **Exact text, numbers or UI copy:** if it must be exact (charts, diagrams, real UI), build it in HTML/SVG instead.
- **Look before you report:** open the image and check spelling, hands and faces, logos, cropping and aspect. Fix it with `edit` if needed. Report the saved path and call it a generated draft.
- **Project assets:** write straight into the project's asset folder with a sensible name. Don't overwrite existing files unless asked. Existing outputs are never overwritten; imagegenkit adds `-2`, `-3` and so on.
- **Prompts:** 2–5 sentences of plain prose covering subject, setting, style, composition and light. Put required text in quotes. For edits, say what must stay unchanged.
- **Errors:** read the provider's message and adjust; don't retry blindly. A moderation block means stop and tell the user.

## Output

Saved paths go to stdout, one per line. With no `-o`, files go to `~/Pictures/ImageGenKit/<date>/`. Every run is logged to `~/.config/imagegenkit/log.jsonl`, and the user sees usage, costs and everything generated in ImageGenKit. Reuse a prompt from the log when the user says "like last time".
