# vision-sight — LESSONS.md

> VisionLearn store for the **vision-sight** skill. **Recall BEFORE each run; append AFTER.**
> Synced to VP-SIA via `vp_record_lesson.py` (skill=`vision-sight`) + federated by `vp_sia_federation.py`,
> and folded into the memory mesh by `vision-lessons`. Machine twin: `lessons.jsonl`
> (shape `{ts, scope, lesson, pattern, evidence}`).

<!-- newest lessons first; format: - [WORKED|AVOID|PATTERN] <lesson> -->
- [PATTERN] Camera presence: the vision-LLM camera eye (`look_through_camera`) beats the local OpenCV Haar face-count under occlusion/angle. Verified 2026-06-06 — operator's raised hand occluded the forehead → Haar `faces=0/present=false`, but Gemini correctly read "person present, facing the screen, attentive" (confirmed against the pixels). When the cheap local count and the vision read DISAGREE, trust the vision read for non-frontal/occluded poses; it also diagnoses *why* the count failed (e.g. camera aimed too high). Double-gated (`camera_presence`+`camera_vision`), frame deleted after, `record=False`. QC PASS 0.96.
- [WORKED] Prove the sight pipeline with an UNFAKEABLE nonce: render a random token into an image, ask the vision-LLM to transcribe it, PASS iff the token comes back. A model can only return a random string by actually reading the pixels — settles "does sight really work" with zero ambiguity (`vp_sight_proof.py` section 4).
