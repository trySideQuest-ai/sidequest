# SideQuest Operations Runbook

Rollback procedures and incident response for the SideQuest public release pipeline.

## Rollback Scenarios

### Scenario 1: Bad Plugin Release

**Symptom:** Users report plugin crashes, hook errors, or broken skills after `plugin-v*` release.

**Mitigation:**

1. Identify last known-good plugin version:
   ```bash
   aws s3 ls s3://sidequest-releases/ | grep sidequest-plugin- | sort -k4
   ```

2. Revert `remote-config.json` to point at the prior version:
   ```bash
   aws s3 cp s3://sidequest-releases/config.json /tmp/config.json
   # Edit /tmp/config.json:
   #   "plugin_version": "0.2.0"   → "0.1.9"
   #   "plugin_sha256": "<new>"    → "<prior sha256>"
   #   "plugin_tarball_url": ".../sidequest-plugin-0.2.0.tar.gz" → "sidequest-plugin-0.1.9.tar.gz"
   aws s3 cp /tmp/config.json s3://sidequest-releases/config.json --acl public-read
   ```

3. Invalidate CloudFront for `remote-config.json`:
   ```bash
   aws cloudfront create-invalidation \
     --distribution-id E2J2MF0TAZ6G7F \
     --paths "/config.json" "/remote-config.json"
   ```

4. Plugin `session-start` hook will pick up new remote config within the next Claude session per user. Users auto-downgrade silently.

5. If the bad plugin crashed `session-start` itself, push a fix via `plugin-v<bad>+1` and have users run `/sidequest:sq-update`.

### Scenario 2: Bad App Release

**Symptom:** Users report native app crashes, IPC failures, or missing notifications after `app-v*` release.

**Mitigation:**

1. Identify last known-good DMG in S3:
   ```bash
   aws s3 ls s3://sidequest-releases/ | grep SideQuestApp- | sort -k4
   ```

2. Copy the prior DMG to `SideQuestApp-latest.dmg` (the installer always fetches `-latest`):
   ```bash
   aws s3 cp s3://sidequest-releases/SideQuestApp-1.8.0.dmg \
     s3://sidequest-releases/SideQuestApp-latest.dmg --acl public-read
   ```

3. Invalidate CloudFront:
   ```bash
   aws cloudfront create-invalidation \
     --distribution-id E2J2MF0TAZ6G7F \
     --paths "/SideQuestApp-latest.dmg"
   ```

4. Bump `remote-config.json`'s `app_version` to the reverted version so the update-available banner stops nagging users.

5. Notify users that they should run `/sidequest:sq-update` (or `/sidequest:reinstall`) to pick up the rolled-back app.

### Scenario 3: Bad install.sh

**Symptom:** Fresh installs fail or do the wrong thing.

**Mitigation:**

1. Restore the previous `install.sh` from version control and re-deploy:
   ```bash
   git log --oneline -- scripts/install.sh | head -5
   git checkout <good-sha> -- scripts/install.sh
   ```

2. Re-deploy:
   ```bash
   aws s3 cp scripts/install.sh s3://sidequest-releases/install.sh \
     --content-type text/plain --acl public-read
   aws cloudfront create-invalidation \
     --distribution-id E2J2MF0TAZ6G7F \
     --paths "/install.sh"
   ```

3. Verify live:
   ```bash
   curl -sI https://get.trysidequest.ai/install.sh
   ```

## Supply-Chain Incident Response

**Trigger:** Unauthorized commit to `trySideQuest-ai/sidequest`, or AWS credentials exposed, or malicious release asset detected.

**Immediate actions (first 15 minutes):**

1. Revoke the OIDC IAM role:
   ```bash
   aws iam detach-role-policy \
     --role-name github-oidc-sidequest-releases \
     --policy-arn <attached-policy-arn>
   aws iam delete-role --role-name github-oidc-sidequest-releases
   ```
   This stops any further CI run from uploading to S3.

2. Invalidate all artifacts on CloudFront:
   ```bash
   aws cloudfront create-invalidation \
     --distribution-id E2J2MF0TAZ6G7F \
     --paths "/*"
   ```

3. Make the public repo private while investigating:
   ```bash
   gh api --method PATCH repos/trySideQuest-ai/sidequest -f visibility=private
   ```

4. Rotate all GitHub Secrets in the public repo:
   ```bash
   gh secret list -R trySideQuest-ai/sidequest | awk '{print $1}' | \
     xargs -I {} gh secret delete {} -R trySideQuest-ai/sidequest
   ```

**Follow-up (next 24 hours):**

1. Audit `git log --all` on public repo for unexpected authors or commits.
2. Review CloudTrail for AWS IAM activity in the incident window.
3. Notify users with:
   - What happened
   - Whether they need to take action
   - When service will resume
4. Re-create the OIDC role with tighter trust policy (limit to specific branch/tag pattern).
5. Publish a post-mortem.

## v2.2 Schema Sunset (SCHEMA-03)

After successful rollout of EmbeddingGemma-300m (768-dim) vectors, legacy 384-dim embedding infrastructure is sunset via SCHEMA-03 migration.

**Timeline:**
- Phase 23 ship (v2.2): Migration committed (dry-run-only), not applied
- Days 1-7 post-ship: Observation window — OBS-02 CloudWatch metric tracks legacy traffic
- Day 7+: If zero traffic confirmed ≥7 days, founder applies SCHEMA-03 manually
- Post-apply: Legacy embedding column + index removed from prod RDS

**What happens:**
- `quest_embeddings.embedding vector(384)` column dropped
- `idx_quest_embeddings_hnsw` legacy HNSW index dropped
- `model_version` constraint tightened to single value
- Legacy 384-dim routes no longer possible

**Prerequisites for apply:**
1. OBS-02 metric (`sidequest_api/LegacyVectorModelCount`) shows zero for ≥7 consecutive days
2. E2E-03 coverage gate passes: ≥99% quests embedded with new model
3. Zero schema errors in Lambda logs (no attempts to access dropped column)

**How to apply (founder only):**
```bash
bash server/scripts/apply-schema-03-sunset.sh  # dry-run (default)
DRY_RUN=false bash server/scripts/apply-schema-03-sunset.sh  # apply (only after gates pass)
```

The full sunset playbook is maintained internally; only the gates and apply procedure above are required to coordinate with downstream consumers.

## Monitoring Signals

Watch for these regression indicators after any release:

- **Plugin auto-update failures:** `~/.sidequest/hook-errors.log` entries containing `session-start` stack traces
- **App crashes:** macOS Console.app filter `SideQuestApp` process for signal 11 / SIGABRT
- **Install failures:** Surge in GitHub Issues on public repo tagged `install`
- **API error rate:** CloudWatch Lambda `sidequest-api` 5xx > 1% of requests over 5 min window
- **Embedding rollout health:** CloudWatch metric `sidequest_api/LegacyVectorModelCount` should be zero ≥7 days after v2.2 distribution (gate for SCHEMA-03 sunset)

## Contact

- **Security issues:** see [SECURITY.md](SECURITY.md) — use GitHub Security Advisories.
- **Other issues:** [GitHub Issues](https://github.com/trySideQuest-ai/sidequest/issues).

## Embedding Vector Privacy & Security

Vectors are now part of how we serve relevant tools to developers. They are deliberately less informative than plaintext, but they are not zero-information — this section documents how we handle them.

### What Embeddings Are

- **Query vectors:** 2 × 384-dim float arrays (user message + assistant message, ≤128 tokens each). Computed on-device in the macOS app, sent once to `/quest`, discarded. Never logged, never persisted.
- **Catalog vectors:** 384-dim embeddings of public product-description text. Chunked (≤120 tokens each), stored in the catalog DB, used for semantic search via approximate-nearest-neighbour index.

### Attack Classes & Mitigations

| Attack | Mechanism | Mitigation | Risk |
|--------|-----------|------------|------|
| Embedding inversion | Train a decoder to recover text from a stolen vector | Chunking (≤120 tokens), no user vectors in DB | Low — high attack cost, low-value recovery (public marketing copy) |
| Gradient extraction from logs | Pull gradients out of vectors logged to observability | No vectors logged — only `selection_method` + scalar distance | Low — no vectors are logged |
| Membership inference | Determine whether a specific message was embedded | Ephemeral query vectors, 128-token cap, single use | Low — no persistent vector cache |

### Incident Response: Vector Leak

**Symptom:** catalog DB backup leaked, or embedding table exposed via security audit.

**Immediate actions:**

1. Identify scope:
   - Catalog vectors only → low impact (vectors of public product descriptions). Record an internal post-mortem and continue operations.
   - User query vectors → these are ephemeral by design and should never appear in any backup. If they do, treat as a serious bug.

2. If catalog vectors only:
   - Inversion is computationally expensive. No emergency action required.
   - File a follow-up to evaluate vector quantization or hashing in the next milestone.

3. If query vectors are found anywhere persistent:
   - **Stop.** Audit the request handler for accidental logging or caching paths.
   - Rotate any backups created during the affected window.
   - Disclose to affected users: "We found a path that may have written ephemeral vectors to disk. Vectors carry less information than plaintext, but we have removed the path and rotated affected storage. No action needed on your side."

4. Post-mortem:
   - Root cause: what allowed the vectors to be persisted? (verbose logging, missing redaction, framework default).
   - Fix: redact at the source. Treat any `embedding`-shaped value as sensitive in logs.
   - Open a hardening backlog item: hash vectors before logging, or quantize to INT8.

### Monitoring Signals: Embedding Health

- **Model fetch failures** during import — log line "Failed to load ONNX embedder" or "tokenizer unavailable". Action: confirm Node version ≥ 20 and that the embedding package is installed; bump the import job.
- **Selection-method drift** — events show a high share of `selection_method` values that bypass the vector path (e.g., tag-only fallback). Action: check inference latency in `/quest` and confirm the on-device app is producing vectors.
- **NaN / Infinity in stored vectors** — diagnostic SQL: any embedding row with non-finite components. Action: revalidate the inference path; the inference layer should never write non-finite values.
- **Chunk-count anomalies** during import — fewer chunks per quest than expected, or many quests with zero chunks. Action: re-run the catalog verification script and investigate any uncovered quests.

### Privacy Principle

Vectors are privacy-forward, not privacy-perfect. Conversation text never leaves the device; what reaches the server is a numerical fingerprint of the last message pair. Recovery is computationally expensive and the recovered content (marketing copy on the catalog side, or recent message context on the query side) does not justify the cost. We accept this residual risk and re-assess annually.

### v2.2 Vector Model Migration (Embedding Gemma 768-Dim)

**Model upgrade:** v2.2 replaces the 384-dim MiniLM embedding model with a 768-dim EmbeddingGemma model, enabling higher-quality quest recommendations with a larger context window (256 tokens per side, ~1024 characters).

**Impact on embeddings:**
- Query vectors now 768-dim instead of 384-dim. Larger vector space increases semantic precision for matching quests to developer context.
- Context window doubles from 128 → 256 tokens, capturing more developer conversation history for relevance matching.
- Catalog vectors (public product descriptions) also re-embedded at 768-dim to maintain consistency with new query vector space.

**Privacy implications:**
- Larger vector space (768-dim vs 384-dim) increases the theoretical surface area for embedding-inversion attacks if vectors were compromised. However, the core mitigation (no plaintext logging) remains unchanged and eliminates this attack vector in practice.
- Larger context window (1024 chars vs 500 chars) increases input to new attack class ALGEN (LLM-guided embedding reconstruction). Same mitigation applies: plaintext is never logged, and query vectors are ephemeral (single use, discarded after `/quest` call).
- Threats GEIA (gradient extraction) and ALGEN (LLM-guided reconstruction) remain mitigated by the no-logging principle: server never sees plaintext, only numerical vectors discarded after `/quest` returns.

**Verification:**
- Automated privacy test (PRIVACY-02) ensures no accidental plaintext logging of user messages or vectors in server console paths. Runs on every deployment.
- Monitoring: CloudWatch metrics `sidequest_api/LegacyVectorModelCount` (confirms all old 384-dim vectors replaced) and `sidequest_api/EmbeddingModelLoadFailure` (tracks app-side inference failures; if failures exceed 5% of active users, triggers investigation).

**Residual risk:** Same as v2.1 — if server database is compromised, attacker has 768-dim vectors of public product descriptions. Inversion is computationally expensive (requires GPU cluster + days of training). No user conversation text is stored or leakable. Accepted as reasonable tradeoff for 10–15% accuracy improvement in quest matching.

**Legacy model sunset:** After ≥7 days of zero 384-dim traffic post-v2.2 ship, SCHEMA-03 migration removes legacy embedding column and HNSW index from prod database. See "v2.2 Schema Sunset (SCHEMA-03)" section above for timeline and gates.
