#!/usr/bin/env bash
#
# Build deterministic CoreML model for SideQuest embedding inference.
#
# Converts sentence-transformers/all-MiniLM-L6-v2 (PyTorch) to a compiled
# CoreML .mlmodelc directory PLUS the matching vocab.txt, packs both into a
# single deterministic tar.gz, and prints the SHA256 + URL fields the
# operator must patch into config.json after upload to S3.
#
# Why ship vocab.txt inside the same tarball:
#   - WordPieceTokenizer cannot run inference without the BERT vocab file
#   - HuggingFace ships vocab alongside the model checkpoint; pairing them
#     in one artifact guarantees they stay version-locked
#   - Tarball SHA256 already verifies both files atomically — no separate
#     hash needed for vocab
#
# This script does NOT upload to S3. Run it locally on a Mac with Xcode +
# coremltools installed; it produces a deterministic tarball that you then
# `aws s3 cp` and CloudFront-invalidate manually (or via release CI).
#
# Requires (pinned for reproducibility):
#   - macOS with Xcode 15.x (xcrun coremlcompiler)
#   - Python 3 with pinned packages:
#       coremltools==8.1
#       torch==2.1.2
#       transformers==4.36.2
#       sentence-transformers==2.5.1
#
# Determinism notes:
#   - HuggingFace MiniLM revision SHA is pinned (no "latest")
#   - Tarball uses --sort=name and a fixed --mtime to remove timestamps
#   - Two consecutive runs must produce identical SHA256; if not, see
#     RESEARCH Pitfall 1 (Xcode/SDK version drift).

set -euo pipefail

# --- Pinned versions ---------------------------------------------------------

MODEL_VERSION="2.1.0"
MINILM_REVISION="c9745ed1d9f207416be6d2e6f8de32d1f16199bf"

# Output names — versioned so the app can resolve which artifact to load
# from a known cache path.
MLMODEL="minilm-l6-v2-${MODEL_VERSION}.mlmodel"
MLMODELC="minilm-l6-v2-${MODEL_VERSION}.mlmodelc"
VOCAB="minilm-l6-v2-${MODEL_VERSION}-vocab.txt"
TARBALL="minilm-l6-v2-${MODEL_VERSION}.mlmodelc.tar.gz"

# Deterministic tar mtime — the date the script was first written.
# Bumping this changes the tarball SHA256, which invalidates pinned hashes
# in config.json. Only change when intentionally cutting a new model version.
TAR_MTIME="2026-04-25"

# Build directory — script always works in its own cwd. Caller decides where
# to invoke (e.g. cd client/macOS/build && ../scripts/build-coreml-model.sh).
echo "[build] cwd: $(pwd)"
echo "[build] MODEL_VERSION=${MODEL_VERSION}  MINILM_REVISION=${MINILM_REVISION}"

# --- Step 0: tooling preflight ----------------------------------------------

command -v python3 >/dev/null 2>&1 || {
  echo "[build] ERROR: python3 not found on PATH" >&2
  exit 1
}

command -v xcrun >/dev/null 2>&1 || {
  echo "[build] ERROR: xcrun not found — install Xcode + Command Line Tools" >&2
  exit 1
}

command -v shasum >/dev/null 2>&1 || {
  echo "[build] ERROR: shasum not found (macOS built-in)" >&2
  exit 1
}

# Verify Python deps are importable; surface a clear install hint if not.
python3 - <<'PYTHON' || { echo "[build] ERROR: missing Python deps. Install with: pip install coremltools==8.1 torch==2.1.2 transformers==4.36.2 sentence-transformers==2.5.1" >&2; exit 1; }
import importlib.util
import sys
required = ["coremltools", "torch", "transformers", "sentence_transformers"]
missing = [m for m in required if importlib.util.find_spec(m) is None]
if missing:
    sys.exit("missing: " + ",".join(missing))
PYTHON

# --- Step 1: download pinned MiniLM checkpoint ------------------------------

echo "[build] step 1: load sentence-transformers/all-MiniLM-L6-v2 @ ${MINILM_REVISION}"
python3 - <<PYTHON
from sentence_transformers import SentenceTransformer
SentenceTransformer(
    'sentence-transformers/all-MiniLM-L6-v2',
    revision='${MINILM_REVISION}',
    device='cpu',
)
print('[build] checkpoint loaded')
PYTHON

# --- Step 2: trace + convert to CoreML, emit vocab --------------------------

# Clean any prior artifacts so SHA256 is computed on a fresh build.
rm -rf "${MLMODEL}" "${MLMODELC}" "${VOCAB}" "${TARBALL}"

echo "[build] step 2: trace PyTorch graph + convert to CoreML, emit vocab"
python3 - <<PYTHON
import os
import shutil
import numpy as np
import torch
import coremltools as ct
from sentence_transformers import SentenceTransformer
from transformers import AutoTokenizer

model = SentenceTransformer(
    'sentence-transformers/all-MiniLM-L6-v2',
    revision='${MINILM_REVISION}',
    device='cpu',
)
model.eval()

# BertModel.forward defaults to return_dict=True (returns BaseModelOutput
# dict). torch.jit.trace cannot capture dict outputs reliably — flip the
# config to return tuples before tracing.
model[0].auto_model.config.return_dict = False


# Wrap the BertModel so the traced graph emits a single 384-dim sentence
# embedding tensor named "embeddings", matching the server-side
# @xenova/transformers feature-extraction pipeline (mean pool over tokens
# with attention mask + L2 normalize). Without this wrapper, BertModel
# returns 2 tensors (last_hidden_state, pooler_output) and ct.convert
# rejects the single-output declaration. Mean pool is what
# sentence-transformers ships as the canonical pooling for MiniLM L6 v2 —
# CLS pooler_output is not used downstream.
class MeanPoolWrapper(torch.nn.Module):
    def __init__(self, bert):
        super().__init__()
        self.bert = bert

    def forward(self, input_ids):
        # Treat any non-zero token id as real (pad token id = 0 for BERT
        # WordPiece). Matches the WordPieceTokenizer pad behavior on the
        # client side.
        attention_mask = (input_ids != 0).to(torch.float32)
        outputs = self.bert(input_ids=input_ids, attention_mask=attention_mask)
        last_hidden_state = outputs[0]
        mask = attention_mask.unsqueeze(-1)
        summed = (last_hidden_state * mask).sum(dim=1)
        counts = mask.sum(dim=1).clamp(min=1e-9)
        pooled = summed / counts
        normalized = torch.nn.functional.normalize(pooled, p=2, dim=1)
        return normalized


wrapped = MeanPoolWrapper(model[0].auto_model)
wrapped.eval()

# MiniLM L6 was trained at max_length=128. Trace with that exact shape.
example_input = torch.randint(0, 100, (1, 128), dtype=torch.int32)
traced = torch.jit.trace(wrapped, (example_input,))

ml_model = ct.convert(
    traced,
    convert_to='mlprogram',
    compute_units=ct.ComputeUnit.CPU_AND_NE,
    inputs=[ct.TensorType(shape=(1, 128), dtype=np.int32, name='input_ids')],
    outputs=[ct.TensorType(name='embeddings')],
)
ml_model.save('${MLMODEL}')
print('[build] saved ${MLMODEL}')

# WordPieceTokenizer on macOS reads vocab.txt at runtime. Pin to the same
# revision so vocab indices match the traced model exactly.
tokenizer = AutoTokenizer.from_pretrained(
    'sentence-transformers/all-MiniLM-L6-v2',
    revision='${MINILM_REVISION}',
)
vocab_paths = tokenizer.save_vocabulary('.')
src = next((p for p in vocab_paths if os.path.basename(p) == 'vocab.txt'), None)
if not src:
    raise RuntimeError(
        'vocab.txt not in tokenizer.save_vocabulary output: ' + repr(vocab_paths)
    )
shutil.copyfile(src, '${VOCAB}')
print('[build] saved ${VOCAB}')
PYTHON

# --- Step 3: compile .mlmodel -> .mlmodelc ----------------------------------

echo "[build] step 3: xcrun coremlcompiler compile -> ${MLMODELC}"
xcrun coremlcompiler compile "${MLMODEL}" .
# coremlcompiler emits the .mlmodelc directly (named after input minus ext).
[ -d "${MLMODELC}" ] || {
  echo "[build] ERROR: expected ${MLMODELC} after compile, not found" >&2
  exit 1
}

# --- Step 4: deterministic tarball (model dir + vocab.txt) ------------------

[ -f "${VOCAB}" ] || {
  echo "[build] ERROR: ${VOCAB} not present at tar time" >&2
  exit 1
}

echo "[build] step 4: deterministic tar (sort=name, mtime=${TAR_MTIME}, owner=0)"
tar --sort=name \
    --mtime="${TAR_MTIME}" \
    --owner=0 --group=0 \
    --numeric-owner \
    -czf "${TARBALL}" \
    "${MLMODELC}" \
    "${VOCAB}"

# --- Step 5: verify size + emit SHA256 + URL hint ---------------------------

SIZE_BYTES=$(stat -f%z "${TARBALL}" 2>/dev/null || stat -c%s "${TARBALL}" 2>/dev/null || echo 0)
SIZE_HUMAN=$(du -h "${TARBALL}" | cut -f1)
SHA256=$(shasum -a 256 "${TARBALL}" | cut -d' ' -f1)

echo ""
echo "[build] DONE"
echo "[build] tarball:   ${TARBALL}"
echo "[build] size:      ${SIZE_HUMAN} (${SIZE_BYTES} bytes)"
echo "[build] sha256:    ${SHA256}"
echo ""
echo "[build] Next steps (manual, NOT run by this script):"
echo "  aws s3 cp ${TARBALL} s3://sidequest-releases/models/${TARBALL} --region us-east-1"
echo "  aws cloudfront create-invalidation --distribution-id E2J2MF0TAZ6G7F --paths '/models/*' '/config.json' --region us-east-1"
echo "  Patch config.json on S3:"
echo "    model_url    = \"https://get.trysidequest.ai/models/${TARBALL}\""
echo "    model_sha256 = \"${SHA256}\""
echo "  Verify by running this script a second time — SHA256 must match exactly."
