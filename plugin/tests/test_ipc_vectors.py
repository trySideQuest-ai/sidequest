"""Tests for IPC vector handling and validation."""

import json
import pytest
from pathlib import Path
import sys

# Add plugin hooks to path
hooks_path = Path(__file__).parent.parent / 'hooks'
sys.path.insert(0, str(hooks_path))

from ipc_utils import (
  validate_vector,
  serialize_vector,
  deserialize_vector,
  build_ipc_request,
  validate_ipc_response,
  extract_vectors_for_server,
)


class TestVectorValidation:
  """Test vector validation logic."""

  def test_validate_valid_384dim_vector(self):
    """Valid 384-dim vector (v2.1 legacy) passes."""
    vec = [0.5] * 384
    assert validate_vector(vec)

  def test_validate_valid_768dim_vector(self):
    """Valid 768-dim vector (v2.2 EmbeddingGemma) passes."""
    vec = [0.5] * 768
    assert validate_vector(vec)

  def test_validate_wrong_length(self):
    """Wrong length (not 384 or 768) fails."""
    vec = [0.5] * 100
    assert not validate_vector(vec)
    vec = [0.5] * 512
    assert not validate_vector(vec)

  def test_validate_nan(self):
    """NaN fails validation (384-dim)."""
    vec = [0.5] * 384
    vec[0] = float('nan')
    assert not validate_vector(vec)

  def test_validate_nan_768dim(self):
    """NaN fails validation (768-dim)."""
    vec = [0.5] * 768
    vec[0] = float('nan')
    assert not validate_vector(vec)

  def test_validate_inf(self):
    """Infinity fails validation (384-dim)."""
    vec = [0.5] * 384
    vec[0] = float('inf')
    assert not validate_vector(vec)

  def test_validate_inf_768dim(self):
    """Infinity fails validation (768-dim)."""
    vec = [0.5] * 768
    vec[0] = float('inf')
    assert not validate_vector(vec)

  def test_validate_non_list(self):
    """Non-list fails."""
    assert not validate_vector("not a list")
    assert not validate_vector(None)


class TestVectorSerialization:
  """Test JSON serialization at 6-decimal precision."""

  def test_serialize_precision(self):
    """Serialized vectors use 6-decimal format."""
    vec = [0.123456789] * 10 + [0.5] * 374
    serialized = serialize_vector(vec)

    assert len(serialized) == 384
    for s in serialized[:10]:
      assert s == "0.123457", f"Expected 0.123457, got {s}"
      assert s.count('.') == 1
      assert len(s.split('.')[1]) == 6

  def test_deserialize_roundtrip(self):
    """Serialization → deserialization preserves precision."""
    original = [i / 1000.0 for i in range(384)]
    serialized = serialize_vector(original)
    deserialized = deserialize_vector(serialized)

    assert deserialized is not None
    assert len(deserialized) == 384

    # Check cosine similarity >0.9999
    import math
    dot = sum(a * b for a, b in zip(original, deserialized))
    norm_orig = math.sqrt(sum(a * a for a in original))
    norm_deser = math.sqrt(sum(a * a for a in deserialized))
    cosine = dot / (norm_orig * norm_deser + 1e-6)
    assert cosine > 0.9999, f"Cosine similarity {cosine} < 0.9999"

  def test_deserialize_invalid_length(self):
    """Invalid length returns None."""
    strings = ["0.5"] * 100
    assert deserialize_vector(strings) is None

  def test_deserialize_invalid_number(self):
    """Invalid float string returns None."""
    strings = ["0.5"] * 383 + ["not_a_number"]
    assert deserialize_vector(strings) is None


class TestIPCRequest:
  """Test IPC request building."""

  def test_build_request_basic(self):
    """Build request with messages."""
    req = build_ipc_request(
      user_msg="test user",
      asst_msg="test assistant",
      tags=[{"slug": "python", "weight": 0.8}],
      freshness=0.5,
    )

    assert req["user_msg"] == "test user"
    assert req["asst_msg"] == "test assistant"
    assert len(req["tags"]) == 1
    assert req["freshness"] == 0.5

  def test_build_request_truncation(self):
    """Messages truncated to 1024 chars (increased from 500 per IPC-01)."""
    long_msg = "x" * 2000
    req = build_ipc_request(user_msg=long_msg)
    assert len(req["user_msg"]) == 1024

  def test_build_request_both_messages_truncated(self):
    """Both user and assistant messages truncated to 1024 chars."""
    long_user = "u" * 2000
    long_asst = "a" * 2000
    req = build_ipc_request(user_msg=long_user, asst_msg=long_asst)
    assert len(req["user_msg"]) == 1024
    assert len(req["asst_msg"]) == 1024


class TestIPCResponseValidation:
  """Test IPC response validation."""

  def test_validate_response_with_384dim_vectors(self):
    """Response with valid 384-dim vectors (v2.1) passes."""
    response = {
      "user_vec": [0.5] * 384,
      "asst_vec": [0.5] * 384,
      "inference_ms": 45,
    }
    assert validate_ipc_response(response)

  def test_validate_response_with_768dim_vectors(self):
    """Response with valid 768-dim vectors (v2.2) passes."""
    response = {
      "user_vec": [0.5] * 768,
      "asst_vec": [0.5] * 768,
      "inference_ms": 45,
    }
    assert validate_ipc_response(response)

  def test_validate_response_mixed_dim(self):
    """Response with one 384-dim, one 768-dim passes (length-route server-side)."""
    response = {
      "user_vec": [0.5] * 384,
      "asst_vec": [0.5] * 768,
      "inference_ms": 50,
    }
    assert validate_ipc_response(response)

  def test_validate_response_null_vectors(self):
    """Response with null vectors passes (graceful degradation)."""
    response = {
      "user_vec": None,
      "asst_vec": None,
      "inference_ms": 1501,
      "error": "timeout",
    }
    assert validate_ipc_response(response)

  def test_validate_response_mixed(self):
    """Response with one vector valid, one null."""
    response = {
      "user_vec": [0.5] * 768,
      "asst_vec": None,
    }
    assert validate_ipc_response(response)

  def test_validate_response_invalid_vector(self):
    """Response with invalid vector fails."""
    response = {
      "user_vec": [0.5] * 100,  # Wrong length
      "asst_vec": None,
    }
    assert not validate_ipc_response(response)


class TestExtractVectors:
  """Test vector extraction for server."""

  def test_extract_valid_384dim_vectors(self):
    """Extract both 384-dim vectors."""
    response = {
      "user_vec": [0.5] * 384,
      "asst_vec": [0.6] * 384,
    }
    result = extract_vectors_for_server(response)
    assert result["user_vec"] is not None
    assert result["asst_vec"] is not None

  def test_extract_valid_768dim_vectors(self):
    """Extract both 768-dim vectors."""
    response = {
      "user_vec": [0.5] * 768,
      "asst_vec": [0.6] * 768,
    }
    result = extract_vectors_for_server(response)
    assert result["user_vec"] is not None
    assert result["asst_vec"] is not None

  def test_extract_mixed_dim_passthrough(self):
    """Mixed dimension vectors pass through unchanged (server length-routes)."""
    response = {
      "user_vec": [0.5] * 384,
      "asst_vec": [0.6] * 768,
    }
    result = extract_vectors_for_server(response)
    assert result["user_vec"] is not None
    assert len(result["user_vec"]) == 384
    assert result["asst_vec"] is not None
    assert len(result["asst_vec"]) == 768

  def test_extract_null_on_invalid(self):
    """Invalid vector becomes null in result."""
    response = {
      "user_vec": [0.5] * 100,  # Invalid length
      "asst_vec": [0.6] * 768,  # Valid
    }
    result = extract_vectors_for_server(response)
    assert result["user_vec"] is None
    assert result["asst_vec"] is not None

  def test_extract_both_null_on_missing(self):
    """Missing vectors result in null."""
    response = {}
    result = extract_vectors_for_server(response)
    assert result["user_vec"] is None
    assert result["asst_vec"] is None
