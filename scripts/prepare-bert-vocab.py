#!/usr/bin/env python3
"""
Script to download and prepare BERT vocab.txt for bundling in SideQuestApp.

This script downloads the official BERT vocab from sentence-transformers
and prepares it for inclusion in the macOS app bundle.

Installation:
  pip install sentence-transformers transformers

Usage:
  python3 prepare-bert-vocab.py <output_dir>

Output:
  - vocab.txt: BERT vocabulary (one token per line, 30522 tokens)
  - vocab.txt.sha256: SHA256 hash of vocab.txt

The vocab.txt should be copied to:
  client/macOS/SideQuestApp/Resources/vocab.txt

And the SHA256 hash should be added to the app's Info.plist or build config.
"""

import hashlib
import os
import sys
import json
from pathlib import Path


def download_and_prepare_vocab(output_dir: str):
  """Download BERT vocab from sentence-transformers and save locally."""
  try:
    from transformers import AutoTokenizer
  except ImportError:
    print("ERROR: transformers library not found.")
    print("Install with: pip install transformers sentence-transformers")
    return False

  try:
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    # Load the tokenizer from HuggingFace
    print("Downloading sentence-transformers/all-MiniLM-L6-v2 tokenizer...")
    tokenizer = AutoTokenizer.from_pretrained(
        "sentence-transformers/all-MiniLM-L6-v2",
        cache_dir=str(output_path / ".cache")
    )

    # Get vocabulary
    vocab = tokenizer.get_vocab()
    print(f"Loaded vocabulary: {len(vocab)} tokens")

    # Write vocab.txt (format: one token per line, in order by ID)
    vocab_file = output_path / "vocab.txt"
    print(f"Writing vocab.txt to {vocab_file}")

    # Sort by ID (value) to maintain token order
    tokens_by_id = sorted(vocab.items(), key=lambda x: x[1])
    with open(vocab_file, 'w') as f:
      for token, token_id in tokens_by_id:
        f.write(token + '\n')

    # Compute SHA256
    print("Computing SHA256 hash...")
    sha256_hash = hashlib.sha256()
    with open(vocab_file, 'rb') as f:
      for chunk in iter(lambda: f.read(4096), b''):
        sha256_hash.update(chunk)

    hex_hash = sha256_hash.hexdigest()
    print(f"SHA256: {hex_hash}")

    # Write hash file
    hash_file = output_path / "vocab.txt.sha256"
    with open(hash_file, 'w') as f:
      f.write(hex_hash + '\n')

    print(f"\nVocab prepared successfully!")
    print(f"Output: {vocab_file}")
    print(f"SHA256: {hash_file}")
    print(f"\nNext steps:")
    print(f"1. Copy {vocab_file} to client/macOS/SideQuestApp/Resources/vocab.txt")
    print(f"2. Add this SHA256 to your build config: {hex_hash}")
    print(f"3. Update WordPieceTokenizer init to use the hash")

    return True

  except Exception as e:
    print(f"ERROR: {e}")
    import traceback
    traceback.print_exc()
    return False


if __name__ == '__main__':
  output_dir = sys.argv[1] if len(sys.argv) > 1 else "."
  success = download_and_prepare_vocab(output_dir)
  sys.exit(0 if success else 1)
