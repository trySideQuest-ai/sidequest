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

5. If the bad plugin crashed `session-start` itself, push a fix via `plugin-v<bad>+1` and have users run `/sidequest:reinstall`.

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

5. Message pilot channel: "Rolled back to v1.8.0. Run `/sidequest:reinstall` to reinstall the stable app."

### Scenario 3: Bad install.sh

**Symptom:** Fresh installs fail or do the wrong thing.

**Mitigation:**

1. Restore from the private monorepo:
   ```bash
   cd /Users/tomershavit/sidequest-ai
   git log --oneline scripts/install.sh | head -5
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

**Trigger:** Unauthorized commit to `tomer-shavit/sidequest`, or AWS credentials exposed, or malicious release asset detected.

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
   gh api --method PATCH repos/tomer-shavit/sidequest -f visibility=private
   ```

4. Rotate all GitHub Secrets in the public repo:
   ```bash
   gh secret list -R tomer-shavit/sidequest | awk '{print $1}' | \
     xargs -I {} gh secret delete {} -R tomer-shavit/sidequest
   ```

**Follow-up (next 24 hours):**

1. Audit `git log --all` on public repo for unexpected authors or commits.
2. Review CloudTrail for AWS IAM activity in the incident window.
3. Notify pilot users via Slack `#sidequest-pilot` and beta email with:
   - What happened
   - Whether they need to take action
   - When service will resume
4. Re-create the OIDC role with tighter trust policy (limit to specific branch/tag pattern).
5. Publish a post-mortem in `.planning/incidents/<date>-<slug>.md`.

## Monitoring Signals

Watch for these regression indicators after any release:

- **Plugin auto-update failures:** `~/.sidequest/hook-errors.log` entries containing `session-start` stack traces
- **App crashes:** macOS Console.app filter `SideQuestApp` process for signal 11 / SIGABRT
- **Install failures:** Surge in GitHub Issues on public repo tagged `install`
- **API error rate:** CloudWatch Lambda `sidequest-api` 5xx > 1% of requests over 5 min window

## Contact

- Primary on-call: 71125175+tomer-shavit@users.noreply.github.com
- Escalation: co-founder (same channel)
- Pilot user channel: Slack `#sidequest-pilot`

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
   - Catalog vectors only → low impact (vectors of public product descriptions). Document in `.planning/incidents/<date>-<slug>.md` and continue operations.
   - User query vectors → these are ephemeral by design and should never appear in any backup. If they do, treat as a serious bug.

2. If catalog vectors only:
   - Inversion is computationally expensive. No emergency action required.
   - File a follow-up to evaluate vector quantization or hashing in the next milestone.

3. If query vectors are found anywhere persistent:
   - **Stop.** Audit the request handler for accidental logging or caching paths.
   - Rotate any backups created during the affected window.
   - Notify pilot users in Slack `#sidequest-pilot`: "We found a path that may have written ephemeral vectors to disk. Vectors carry less information than plaintext, but we have removed the path and rotated affected storage. No action needed on your side."

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

Vectors are privacy-forward, not privacy-perfect. Conversation text never leaves the device; what reaches the server is a 384-dim numerical fingerprint of the last message pair. Recovery is computationally expensive and the recovered content (marketing copy on the catalog side, ≤128 tokens of recent context on the query side) does not justify the cost. We accept this residual risk for v2.1 and re-assess annually.
