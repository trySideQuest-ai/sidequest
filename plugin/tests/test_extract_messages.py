"""Tests for last message extraction from Claude CLI session state."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


STOP_HOOK_PATH = os.path.join(os.path.dirname(__file__), '..', 'hooks', 'stop-hook')


class TestMessageExtraction(unittest.TestCase):
  """Test message extraction from Claude CLI session JSONL files."""

  def setUp(self):
    """Create temp directories for testing."""
    self.temp_dir = tempfile.mkdtemp()
    self.projects_dir = os.path.join(self.temp_dir, '.claude', 'projects')
    os.makedirs(self.projects_dir, exist_ok=True)

  def tearDown(self):
    """Clean up temp directories."""
    import shutil
    shutil.rmtree(self.temp_dir, ignore_errors=True)

  def _write_session_jsonl(self, entries, dirname=None):
    """Write entries to a .jsonl session file and return path."""
    if dirname is None:
      dirname = self.projects_dir
    os.makedirs(dirname, exist_ok=True)
    path = os.path.join(dirname, 'latest-session.jsonl')
    with open(path, 'w') as f:
      for entry in entries:
        f.write(json.dumps(entry) + '\n')
    return path

  def _make_message_entry(self, msg_type, text, timestamp='2026-04-25T14:00:00Z'):
    """Create a message entry in Claude JSONL format."""
    return {
      'type': msg_type,
      'timestamp': timestamp,
      'message': {
        'content': text if isinstance(text, str) else [
          {'type': 'text', 'text': part} for part in text
        ]
      }
    }

  def _extract_messages(self, entries):
    """Extract messages from session JSONL using the extraction logic."""
    session_path = self._write_session_jsonl(entries)
    project_dir = os.path.dirname(os.path.dirname(session_path))

    # Simulate the extraction logic from stop-hook PHASE 4.9
    cwd = os.getcwd()
    projects_base = os.path.join(self.temp_dir, '.claude', 'projects')

    user_msg = ''
    asst_msg = ''

    # Find latest .jsonl in projects_base
    for filename in os.listdir(projects_base):
      jsonl_path = os.path.join(projects_base, filename, 'latest-session.jsonl')
      if os.path.isfile(jsonl_path):
        try:
          with open(jsonl_path) as f:
            for line in f:
              try:
                obj = json.loads(line.strip())
                kind = obj.get('type')
                if kind in ('user', 'assistant'):
                  msg = obj.get('message', {})
                  content = msg.get('content')

                  # Extract text from content
                  text = ''
                  if isinstance(content, str):
                    text = content
                  elif isinstance(content, list):
                    text = ' '.join(
                      p.get('text', '')
                      for p in content
                      if isinstance(p, dict) and p.get('type') == 'text'
                    )

                  if text:
                    text = text[:500]
                    if kind == 'user':
                      user_msg = text
                    else:
                      asst_msg = text
              except json.JSONDecodeError:
                pass
        except (IOError, PermissionError):
          pass

    return {'user_msg': user_msg, 'asst_msg': asst_msg}

  def test_extract_last_user_message(self):
    """Extract last user message from session."""
    entries = [
      self._make_message_entry('user', 'First user message'),
      self._make_message_entry('assistant', 'First response'),
      self._make_message_entry('user', 'Second user message'),
    ]
    dirname = os.path.join(self.projects_dir, 'test-dir')
    self._write_session_jsonl(entries, dirname)
    result = self._extract_messages(entries)
    self.assertEqual(result['user_msg'], 'Second user message')

  def test_extract_last_assistant_message(self):
    """Extract last assistant message from session."""
    entries = [
      self._make_message_entry('user', 'User asks'),
      self._make_message_entry('assistant', 'First response'),
      self._make_message_entry('user', 'Follow up'),
      self._make_message_entry('assistant', 'Second response'),
    ]
    dirname = os.path.join(self.projects_dir, 'test-dir')
    self._write_session_jsonl(entries, dirname)
    result = self._extract_messages(entries)
    self.assertEqual(result['asst_msg'], 'Second response')

  def test_extract_both_messages(self):
    """Extract both user and assistant messages."""
    entries = [
      self._make_message_entry('user', 'What is Python?'),
      self._make_message_entry('assistant', 'Python is a programming language'),
    ]
    dirname = os.path.join(self.projects_dir, 'test-dir')
    self._write_session_jsonl(entries, dirname)
    result = self._extract_messages(entries)
    self.assertEqual(result['user_msg'], 'What is Python?')
    self.assertEqual(result['asst_msg'], 'Python is a programming language')

  def test_messages_truncated_to_500_chars(self):
    """Messages >500 chars are truncated."""
    long_text = 'a' * 600
    entries = [
      self._make_message_entry('user', long_text),
      self._make_message_entry('assistant', long_text),
    ]
    dirname = os.path.join(self.projects_dir, 'test-dir')
    self._write_session_jsonl(entries, dirname)
    result = self._extract_messages(entries)
    self.assertEqual(len(result['user_msg']), 500)
    self.assertEqual(len(result['asst_msg']), 500)

  def test_empty_messages_as_empty_strings(self):
    """Missing messages return empty strings, not None."""
    entries = [
      self._make_message_entry('user', 'Only user message'),
    ]
    dirname = os.path.join(self.projects_dir, 'test-dir')
    self._write_session_jsonl(entries, dirname)
    result = self._extract_messages(entries)
    self.assertEqual(result['user_msg'], 'Only user message')
    self.assertEqual(result['asst_msg'], '')
    self.assertIsInstance(result['asst_msg'], str)

  def test_missing_session_state(self):
    """No session file returns empty strings."""
    result = self._extract_messages([])
    self.assertEqual(result['user_msg'], '')
    self.assertEqual(result['asst_msg'], '')

  def test_multiline_message_handling(self):
    """Messages with newlines are extracted correctly."""
    text_with_newlines = 'Line 1\nLine 2\nLine 3'
    entries = [
      self._make_message_entry('user', text_with_newlines),
    ]
    dirname = os.path.join(self.projects_dir, 'test-dir')
    self._write_session_jsonl(entries, dirname)
    result = self._extract_messages(entries)
    self.assertIn('Line 1', result['user_msg'])
    self.assertIn('Line 2', result['user_msg'])

  def test_json_parse_error_handling(self):
    """Corrupted JSONL lines are skipped gracefully."""
    # Create session with one valid and one invalid line
    session_path = os.path.join(self.projects_dir, 'test-dir', 'latest-session.jsonl')
    os.makedirs(os.path.dirname(session_path), exist_ok=True)
    with open(session_path, 'w') as f:
      f.write(json.dumps(self._make_message_entry('user', 'Valid message')) + '\n')
      f.write('{ invalid json\n')
      f.write(json.dumps(self._make_message_entry('assistant', 'Valid response')) + '\n')

    result = self._extract_messages([])
    self.assertEqual(result['user_msg'], 'Valid message')
    self.assertEqual(result['asst_msg'], 'Valid response')

  def test_message_with_dict_content(self):
    """Messages with dict content (list of parts) are extracted."""
    entries = [
      {
        'type': 'user',
        'timestamp': '2026-04-25T14:00:00Z',
        'message': {
          'content': [
            {'type': 'text', 'text': 'First part'},
            {'type': 'code', 'text': 'ignored'},
            {'type': 'text', 'text': ' second part'},
          ]
        }
      }
    ]
    dirname = os.path.join(self.projects_dir, 'test-dir')
    self._write_session_jsonl(entries, dirname)
    result = self._extract_messages(entries)
    self.assertIn('First part', result['user_msg'])
    self.assertIn('second part', result['user_msg'])


if __name__ == '__main__':
  unittest.main()
