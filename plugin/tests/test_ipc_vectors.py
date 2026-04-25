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

  def test_validate_valid_vector(self):
    """Valid 384-dim vector passes."""
    vec = [0.5] * 384
    assert validate_vector(vec)

  def test_validate_wrong_length(self):
    """Wrong length fails."""
    vec = [0.5] * 100
    assert not validate_vector(vec)

  def test_validate_nan(self):
    """NaN fails validation."""
    vec = [0.5] * 384
    vec[0] = float('nan')
    assert not validate_vector(vec)

  def test_validate_inf(self):
    """Infinity fails validation."""
    vec = [0.5] * 384
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
    """Messages truncated to 500 chars."""
    long_msg = "x" * 1000
    req = build_ipc_request(user_msg=long_msg)
    assert len(req["user_msg"]) == 500


class TestIPCResponseValidation:
  """Test IPC response validation."""

  def test_validate_response_with_vectors(self):
    """Response with valid vectors passes."""
    response = {
      "user_vec": [0.5] * 384,
      "asst_vec": [0.5] * 384,
      "inference_ms": 45,
    }
    assert validate_ipc_response(response)

  def test_validate_response_null_vectors(self):
    """Response with null vectors passes (graceful degradation)."""
    response = {
      "user_vec": None,
      "asst_vec": None,
      "inference_ms": 1001,
      "error": "timeout",
    }
    assert validate_ipc_response(response)

  def test_validate_response_mixed(self):
    """Response with one vector valid, one null."""
    response = {
      "user_vec": [0.5] * 384,
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

  def test_extract_valid_vectors(self):
    """Extract both vectors."""
    response = {
      "user_vec": [0.5] * 384,
      "asst_vec": [0.6] * 384,
    }
    result = extract_vectors_for_server(response)
    assert result["user_vec"] is not None
    assert result["asst_vec"] is not None

  def test_extract_null_on_invalid(self):
    """Invalid vector becomes null in result."""
    response = {
      "user_vec": [0.5] * 100,  # Invalid length
      "asst_vec": [0.6] * 384,  # Valid
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
