"""IPC utilities for native app communication.

Handles message extraction, vector formatting, and validation for Unix socket IPC.
Ensures 6-decimal precision and validates all vectors before server transmission.
"""

import json
import socket
import os
import math
from pathlib import Path
from typing import Optional, Dict, List, Any


def validate_vector(vec: Any) -> bool:
  """Validate vector for correct shape, dimension, and finite values.

  Args:
    vec: Candidate vector (should be list of floats)

  Returns:
    True if valid 384-dim vector with all finite values
  """
  if not isinstance(vec, list):
    return False
  if len(vec) != 384:
    return False
  for v in vec:
    if not isinstance(v, (int, float)):
      return False
    if math.isnan(float(v)) or math.isinf(float(v)):
      return False
  return True


def serialize_vector(vec: List[float]) -> List[str]:
  """Serialize vector to 6-decimal precision string array.

  Args:
    vec: 384-dim float vector

  Returns:
    List of strings, each formatted as "%.6f"
  """
  if not vec or len(vec) != 384:
    return []
  return [f'{v:.6f}' for v in vec]


def deserialize_vector(strings: List[str]) -> Optional[List[float]]:
  """Deserialize string array back to float vector.

  Args:
    strings: List of "%.6f" formatted strings

  Returns:
    384-dim float vector, or None if invalid
  """
  if not strings or len(strings) != 384:
    return None
  vec = []
  for s in strings:
    try:
      vec.append(float(s))
    except ValueError:
      return None
  return vec


def build_ipc_request(
  user_msg: str = '',
  asst_msg: str = '',
  tags: Optional[List[Dict[str, Any]]] = None,
  freshness: float = 0.0
) -> Dict[str, Any]:
  """Build IPC request payload for native app.

  Args:
    user_msg: Last user message from Claude CLI (≤500 chars)
    asst_msg: Last assistant message (≤500 chars)
    tags: Relevance tags with weights
    freshness: Time-based freshness score

  Returns:
    JSON-serializable dict for socket send
  """
  return {
    'user_msg': user_msg[:500],
    'asst_msg': asst_msg[:500],
    'tags': tags or [],
    'freshness': freshness,
  }


def send_ipc_request(payload: Dict[str, Any], socket_path: str = None) -> Optional[Dict[str, Any]]:
  """Send IPC request to native app and receive response.

  Args:
    payload: Request dict
    socket_path: Unix socket path (default ~/.sidequest/sidequest.sock)

  Returns:
    Response dict with user_vec, asst_vec (or None on timeout/error)
  """
  if socket_path is None:
    home = str(Path.home())
    socket_path = os.path.join(home, '.sidequest', 'sidequest.sock')

  if not os.path.exists(socket_path):
    return None

  try:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(1.0)  # 1s round-trip timeout
    sock.connect(socket_path)

    # Send request
    request_json = json.dumps(payload)
    sock.sendall(request_json.encode('utf-8'))

    # Receive response
    response_data = b''
    while True:
      try:
        chunk = sock.recv(4096)
        if not chunk:
          break
        response_data += chunk
      except socket.timeout:
        break

    sock.close()

    if not response_data:
      return None

    response = json.loads(response_data.decode('utf-8'))
    return response

  except (socket.error, json.JSONDecodeError, OSError):
    return None


def validate_ipc_response(response: Dict[str, Any]) -> bool:
  """Validate IPC response before server transmission.

  Args:
    response: Response dict from native app

  Returns:
    True if vectors are valid (or gracefully absent)
  """
  if not response:
    return False

  # Vectors are optional (graceful degradation)
  user_vec = response.get('user_vec')
  asst_vec = response.get('asst_vec')

  if user_vec is not None and not validate_vector(user_vec):
    return False
  if asst_vec is not None and not validate_vector(asst_vec):
    return False

  return True


def extract_vectors_for_server(response: Dict[str, Any]) -> Dict[str, Any]:
  """Extract validated vectors from IPC response for server /quest POST.

  Args:
    response: IPC response dict

  Returns:
    Dict with user_vec, asst_vec (null if invalid/missing)
  """
  result = {
    'user_vec': None,
    'asst_vec': None,
  }

  if not response:
    return result

  user_vec = response.get('user_vec')
  asst_vec = response.get('asst_vec')

  if user_vec is not None and validate_vector(user_vec):
    result['user_vec'] = user_vec
  if asst_vec is not None and validate_vector(asst_vec):
    result['asst_vec'] = asst_vec

  return result
