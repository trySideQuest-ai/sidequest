"""IPC utilities for vector serialization and validation.

Handles JSON serialization of embedding vectors to 6-decimal precision,
validation of vector format/shape, and IPC request/response building.
"""

import json
import math


def validate_vector(vector):
  """Validate a vector for IPC transmission.

  Args:
    vector: list of floats or None

  Returns:
    True if valid 384-dim (v2.1) or 768-dim (v2.2) vector with finite values, False otherwise
  """
  if vector is None:
    return False

  if not isinstance(vector, list):
    return False

  # Accept both legacy 384-dim (MiniLM) and new 768-dim (EmbeddingGemma) per IPC-02
  if len(vector) not in (384, 768):
    return False

  for val in vector:
    if not isinstance(val, (int, float)):
      return False
    if math.isnan(val) or math.isinf(val):
      return False

  return True


def serialize_vector(vector):
  """Serialize vector to JSON string with 6-decimal precision.

  Args:
    vector: list of 384 floats

  Returns:
    List of 384 strings formatted to 6 decimals
  """
  if not validate_vector(vector):
    return None

  # Format each element to 6 decimals
  return ['{:.6f}'.format(v) for v in vector]


def deserialize_vector(strings):
  """Deserialize string array back to vector list.

  Args:
    strings: list of float strings or list of floats

  Returns:
    List of floats, or None if invalid
  """
  try:
    if not isinstance(strings, list):
      return None

    # Accept both 384-dim (v2.1) and 768-dim (v2.2) per IPC-02
    if len(strings) not in (384, 768):
      return None

    vector = [float(v) for v in strings]
    if validate_vector(vector):
      return vector
  except (ValueError, TypeError):
    pass

  return None


def build_ipc_request(user_msg='', asst_msg='', user_vec=None, asst_vec=None, tags=None, freshness=None):
  """Build IPC request dict with messages and optional vectors.

  Args:
    user_msg: user message text (string, truncated to 1024 chars per IPC-01)
    asst_msg: assistant message text (string, truncated to 1024 chars per IPC-01)
    user_vec: user embedding vector (384 or 768-dim, per IPC-02) or None
    asst_vec: assistant embedding vector (384 or 768-dim, per IPC-02) or None
    tags: list of tag dicts with slug/weight
    freshness: freshness score (0-1)

  Returns:
    Dict for IPC transmission
  """
  payload = {
    'user_msg': (user_msg or '')[:1024],  # Increased from 500 per IPC-01
    'asst_msg': (asst_msg or '')[:1024],  # Increased from 500 per IPC-01
  }

  # Add vectors if both are valid (accept 384 or 768-dim per IPC-02)
  if user_vec is not None and asst_vec is not None:
    if validate_vector(user_vec) and validate_vector(asst_vec):
      payload['user_vec'] = user_vec
      payload['asst_vec'] = asst_vec

  # Add optional fields
  if tags is not None:
    payload['tags'] = tags

  if freshness is not None:
    payload['freshness'] = freshness

  return payload


def validate_ipc_response(response):
  """Validate IPC response structure and vector format.

  Args:
    response: dict from native app or JSON string

  Returns:
    True if response is valid, False otherwise
  """
  # Handle both dict and JSON string
  if isinstance(response, str):
    try:
      response = json.loads(response)
    except (json.JSONDecodeError, TypeError):
      return False

  if not isinstance(response, dict):
    return False

  user_vec = response.get('user_vec')
  asst_vec = response.get('asst_vec')

  # If both vectors are None, that's valid (graceful degradation)
  if user_vec is None and asst_vec is None:
    return True

  # If one vector is None and other is invalid, that's invalid
  if user_vec is None or asst_vec is None:
    # One is present, one is None - check if present one is valid
    present_vec = user_vec if user_vec is not None else asst_vec
    return validate_vector(present_vec)

  # Both vectors present - both must be valid
  return validate_vector(user_vec) and validate_vector(asst_vec)


def extract_vectors_for_server(response):
  """Extract vectors from IPC response for /quest POST.

  Invalid vectors become None in result (graceful degradation).

  Args:
    response: dict from IPC

  Returns:
    Dict with user_vec and asst_vec (or None if invalid)
  """
  if not isinstance(response, dict):
    return {'user_vec': None, 'asst_vec': None}

  user_vec = response.get('user_vec')
  asst_vec = response.get('asst_vec')

  # Validate each vector, set to None if invalid
  return {
    'user_vec': user_vec if validate_vector(user_vec) else None,
    'asst_vec': asst_vec if validate_vector(asst_vec) else None,
  }
