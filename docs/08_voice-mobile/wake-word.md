# Wake Word

## Purpose
Define wake/STT/VAD/TTS chain contract.

## Execution Flow (target)
1. Wake word detection event.
2. Capture audio until VAD stop.
3. STT transcript creation.
4. Submit transcript to unified intake (`ephemeral_request`).
5. Agent result projection and optional TTS playback.

## Status
End-to-end production readiness is incomplete; do not mark as GA.
