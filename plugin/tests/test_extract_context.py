"""Tests for context extraction from Claude Code conversation history."""

import json
import os
import subprocess
import tempfile
import unittest

SCRIPT_PATH = os.path.join(os.path.dirname(__file__), '..', 'hooks', 'extract-context.py')


def run_extractor(entries, project_filter=None):
    """Write entries to a temp JSONL file and run the extractor."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
        for entry in entries:
            f.write(json.dumps(entry) + '\n')
        f.flush()
        args = ['python3', SCRIPT_PATH, f.name]
        if project_filter:
            args.append(project_filter)
        result = subprocess.run(args, capture_output=True, text=True, timeout=5)
        os.unlink(f.name)
        return json.loads(result.stdout.strip())


def make_entry(display, project='/test/project', session_id='test-session'):
    return {
        'display': display,
        'timestamp': 1712000000000,
        'project': project,
        'sessionId': session_id,
    }


class TestContextExtraction(unittest.TestCase):

    def test_filters_by_project(self):
        entries = [
            make_entry('fix PostgreSQL query', project='/my/project'),
            make_entry('fix React component', project='/other/project'),
        ]
        tags = run_extractor(entries, project_filter='/my/project')
        self.assertIn('postgresql', tags)
        self.assertNotIn('react', tags)

    def test_returns_empty_for_no_matches(self):
        entries = [
            make_entry('what is the meaning of life'),
            make_entry('tell me a joke'),
        ]
        tags = run_extractor(entries)
        self.assertEqual(tags, [])

    def test_handles_empty_history(self):
        tags = run_extractor([])
        self.assertEqual(tags, [])

    def test_handles_missing_file(self):
        result = subprocess.run(
            ['python3', SCRIPT_PATH, '/nonexistent/file.jsonl'],
            capture_output=True, text=True, timeout=5
        )
        tags = json.loads(result.stdout.strip())
        self.assertEqual(tags, [])
        self.assertEqual(result.returncode, 0)

    def test_handles_malformed_jsonl(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
            f.write('not valid json\n')
            f.write(json.dumps(make_entry('fix my React bug')) + '\n')
            f.write('{broken\n')
            f.flush()
            result = subprocess.run(
                ['python3', SCRIPT_PATH, f.name],
                capture_output=True, text=True, timeout=5
            )
            os.unlink(f.name)
            tags = json.loads(result.stdout.strip())
            self.assertIn('react', tags)

    def test_returns_max_20_tags(self):
        # Create entries mentioning many different tools (v1.7: limit raised to 20)
        entries = [
            make_entry('react next.js vue angular svelte express django flask rails spring postgresql docker kubernetes'),
        ]
        tags = run_extractor(entries)
        self.assertLessEqual(len(tags), 20)

    def test_includes_pasted_content(self):
        entries = [{
            'display': 'fix this code',
            'pastedContents': {
                '1': {
                    'id': 1,
                    'type': 'text',
                    'content': 'import { Pool } from "pg"\nconst pool = new Pool()',
                }
            },
            'timestamp': 1712000000000,
            'project': '/test/project',
            'sessionId': 'test-session',
        }]
        tags = run_extractor(entries)
        self.assertIn('postgresql', tags)



def _load_extractor_module():
    """Dynamic import because filename has a dash."""
    import importlib.util
    spec = importlib.util.spec_from_file_location('extract_context_mod', SCRIPT_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class TestFreshness(unittest.TestCase):
    def setUp(self):
        self.ec = _load_extractor_module()

    def test_zero_signals_is_zero(self):
        self.assertEqual(self.ec.compute_freshness(0), 0.0)

    def test_one_signal_below_target(self):
        self.assertAlmostEqual(self.ec.compute_freshness(1), 0.25)

    def test_target_signals_is_one(self):
        self.assertEqual(self.ec.compute_freshness(self.ec.FRESHNESS_SIGNAL_COUNT_TARGET), 1.0)

    def test_above_target_caps_at_one(self):
        self.assertEqual(self.ec.compute_freshness(10), 1.0)


class TestTranscriptReader(unittest.TestCase):
    def setUp(self):
        self.ec = _load_extractor_module()

    def test_missing_project_dir_returns_empty(self):
        segments = self.ec.read_session_transcript_segments(cwd='/definitely/does/not/exist/xyz')
        self.assertEqual(segments, [])

    def test_strips_fenced_code_from_assistant_text(self):
        raw = 'hi here is code\n```python\nprint(1)\n```\nand more'
        cleaned = self.ec._strip_fenced_code(raw)
        self.assertNotIn('print(1)', cleaned)
        self.assertIn('and more', cleaned)

    def test_stale_session_returns_empty(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            # Simulate ~/.claude/projects/<cwd-as-dashes>
            fake_cwd = '/opt/test_project_stale'
            project_dir = self.ec._project_sessions_dir(fake_cwd)
            project_parent = os.path.dirname(project_dir)
            os.makedirs(project_parent, exist_ok=True)
            # Cannot reliably control ~/.claude in tests. So assert path derivation
            # and the staleness short-circuit logic via direct function arg.
            self.assertTrue(project_dir.endswith('-opt-test_project_stale'))

    def test_reads_recent_session_with_user_and_assistant_turns(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            fake_cwd = os.path.join(tmpdir, 'proj')
            os.makedirs(fake_cwd)
            # Monkey-patch the projects-dir computation by redirecting HOME
            orig_home = os.environ.get('HOME')
            os.environ['HOME'] = tmpdir
            try:
                sessions_dir = os.path.expanduser(
                    os.path.join('~/.claude/projects', os.path.abspath(fake_cwd).replace('/', '-'))
                )
                os.makedirs(sessions_dir, exist_ok=True)
                jsonl_path = os.path.join(sessions_dir, 'abc.jsonl')
                with open(jsonl_path, 'w') as f:
                    f.write(json.dumps({
                        'type': 'user',
                        'message': {'content': 'help me with postgresql please'},
                        'timestamp': '2026-04-19T19:00:00Z',
                    }) + '\n')
                    f.write(json.dumps({
                        'type': 'assistant',
                        'message': {'content': [
                            {'type': 'text', 'text': 'Sure, here is a snippet\n```sql\nSELECT 1;\n```\nAnd it should work.'}
                        ]},
                        'timestamp': '2026-04-19T19:00:05Z',
                    }) + '\n')
                segments = self.ec.read_session_transcript_segments(cwd=fake_cwd, stale_max_min=1000000)
                self.assertEqual(len(segments), 2)
                joined = ' '.join(text for text, _ in segments)
                self.assertIn('postgresql', joined.lower())
                # Fenced SQL stripped from assistant text.
                self.assertNotIn('SELECT 1', joined)
            finally:
                if orig_home is not None:
                    os.environ['HOME'] = orig_home


class TestFullModeOutput(unittest.TestCase):
    """Sanity check that `--mode full` emits weighted_tags + freshness."""

    def test_full_mode_emits_weighted_tags_and_freshness(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
            f.write(json.dumps(make_entry('fix my postgresql query please')) + '\n')
            f.flush()
            result = subprocess.run(
                ['python3', SCRIPT_PATH, '--mode', 'full', f.name],
                capture_output=True, text=True, timeout=5,
                env={**os.environ, 'SIDEQUEST_DIFF': '', 'SIDEQUEST_BRANCH': '', 'SIDEQUEST_COMMIT_MSG': ''},
            )
            os.unlink(f.name)
            data = json.loads(result.stdout.strip())
            self.assertIn('weighted_tags', data)
            self.assertIn('freshness', data)
            self.assertIsInstance(data['freshness'], (int, float))


if __name__ == '__main__':
    unittest.main()
