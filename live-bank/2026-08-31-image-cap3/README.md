# Live-proven OpenClaw image cap bank - 2026-08-31

These are exact deployed built artifacts copied from the live OpenClaw installation.

## Markers

- FORGE_RECENT_HISTORY_IMAGE_CAP_3_V1
- FORGE_CURRENT_IMAGE_CAP_3_V1
- FORGE_MEDIA_PATH_IMAGE_CAP_3_V1

## Behaviour

- Caps automatic recent-history images at 3
- Caps automatic current-message images at 3
- Exposes prompt-visible local paths for no more than 3 images
- Preserves the total attachment count
- Reports how many additional images were omitted
- Allows omitted images to be retrieved deliberately when required

## Live proof

- A later text mention did not drag an earlier image into native vision
- A current single image remained available as native vision input
- A multi-image prompt exposed only the first 3 paths and reported the omitted count

Workbench behaviour is not equivalent to live Discord and Sentry session continuity or model routing. Any behavioural regression must be reproduced on the live Discord path before changing these fixes.

## SHA256

- agent-turn-attachments-wVL0VVTp.js: 92DF34F92AEFCE24B8CC09CC363F9FD3DE29F0EDCE3A358DB21D26EEE58BCBDF
- get-reply-CknL88Yv.js: 39ACE67C6381DFD75999596518B9270553C7C6FA3AA3A82EBC80F8BE4E18A3E3
