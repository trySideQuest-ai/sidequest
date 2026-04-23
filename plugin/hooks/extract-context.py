"""
Data-driven context extractor — reads multiple sources (conversation, diff,
git metadata, config cache) and extracts weighted developer tool tags via
config-driven pattern matching.

Open/Closed: adding a new tag, domain, or config file rule is a JSON edit
in config/ — never a code change.

Input modes (via --mode flag):
  conversation: history file path (arg 1), project dir filter (arg 2, optional)
  diff:         reads diff text from stdin
  git_metadata: reads branch name + commit message from stdin
  full:         all sources — args: history_path [project_dir]
                reads diff from env SIDEQUEST_DIFF, git metadata from env vars

Output: JSON with weighted_tags array and domain string
Exit:   Always exits 0. Errors produce empty result.
"""

import json
import math
import os
import re
import sys
import time


# Module-level constants with explanations
DEFAULT_MAX_DIFF_BYTES = 51200          # 50 KB diff cap (per CLAUDE.md pragmatism)
DEFAULT_MAX_CONVERSATION_ENTRIES = 100  # Max history entries to process
DEFAULT_MAX_OUTPUT_TAGS = 20            # Max tags in output
FRESHNESS_SIGNAL_COUNT_TARGET = 4       # Target signal count for full freshness


def _log_debug(msg):
  """Write to stderr only when SIDEQUEST_DEBUG=1 env var is set."""
  if os.environ.get('SIDEQUEST_DEBUG') == '1':
    print(msg, file=sys.stderr)


def load_config(name):
  """Load a JSON config file from the config/ directory."""
  config_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'config')
  path = os.path.join(config_dir, name)
  with open(path) as f:
    return json.load(f)


def load_all_configs():
  """Load all three config files (patterns, sources, domains)."""
  return {
    'patterns': load_config('patterns.json'),
    'sources': load_config('sources.json'),
    'domains': load_config('domains.json'),
  }


class PatternMatcher:
  """Compiles tag patterns from config and matches text against them."""

  def __init__(self, patterns_config):
    self._compiled = []
    for tag_def in patterns_config['tags']:
      combined = '|'.join('(?:' + p + ')' for p in tag_def['patterns'])
      regex = re.compile(combined, re.IGNORECASE)
      self._compiled.append((regex, tag_def['slug']))

  def match(self, text):
    """Return set of tag slugs found in text."""
    found = set()
    for regex, slug in self._compiled:
      if regex.search(text):
        found.add(slug)
    return found


def _age_min_from_timestamp_ms(ts_ms, now_ms):
  """Convert timestamp in ms since epoch to age in minutes."""
  if ts_ms is None or ts_ms <= 0:
    return 0
  return max(0, (now_ms - ts_ms) / 60000.0)


_FENCED_CODE_RE = re.compile(r'```.*?```', re.DOTALL)


def _strip_fenced_code(text):
  """Remove fenced code blocks from text."""
  if not text:
    return ''
  return _FENCED_CODE_RE.sub(' ', text)


def _project_sessions_dir(cwd):
  """Map cwd '/Users/tomer/proj' → '~/.claude/projects/-Users-tomer-proj'."""
  normalized = os.path.abspath(cwd).replace('/', '-')
  return os.path.expanduser(os.path.join('~/.claude/projects', normalized))


def _read_history_jsonl_lines(path):
  """Yield parsed JSONL dicts from history file, None on parse error."""
  try:
    with open(path) as f:
      for line in f:
        line = line.strip()
        if not line:
          continue
        try:
          yield json.loads(line)
        except json.JSONDecodeError:
          yield None
  except (IOError, PermissionError):
    return


def _filter_entries_by_project(entries, project_filter):
  """Filter entries by project (or return all if no filter)."""
  if not project_filter:
    return entries
  return [e for e in entries if e.get('project') == project_filter]


def _entry_to_segments(entry, now_ms):
  """Convert one history entry to (text, age_min) segments."""
  if not entry:
    return []
  age_min = _age_min_from_timestamp_ms(entry.get('timestamp'), now_ms)
  segments = []
  text = entry.get('display', '')
  if text:
    segments.append((text, age_min))
  pasted = entry.get('pastedContents', {})
  if isinstance(pasted, dict):
    for paste in pasted.values():
      if isinstance(paste, dict) and paste.get('content'):
        segments.append((paste['content'], age_min))
  return segments


def read_conversation_segments(history_path, project_filter=None, max_entries=100, now_ms=None):
  """Orchestrator: read, filter by project, segment conversation history."""
  if not history_path or not os.path.exists(history_path):
    return []
  if now_ms is None:
    now_ms = int(time.time() * 1000)
  entries = [e for e in _read_history_jsonl_lines(history_path) if e is not None]
  entries = _filter_entries_by_project(entries, project_filter)[-max_entries:]
  segments = []
  for entry in entries:
    segments.extend(_entry_to_segments(entry, now_ms))
  return segments


def read_diff_segment(diff_text=None, max_bytes=51200):
  """Diff is a single current-state segment (age 0)."""
  if diff_text is None or not diff_text:
    return []
  if len(diff_text) > max_bytes:
    diff_text = diff_text[:max_bytes]
  return [(diff_text, 0)]


def read_git_metadata_segment(branch=None, commit_msg=None):
  """Git metadata is a single segment representing the current session state."""
  parts = []
  if branch:
    parts.append(branch.replace('/', ' ').replace('-', ' ').replace('_', ' '))
  if commit_msg:
    parts.append(commit_msg)
  if not parts:
    return []
  return [(' '.join(parts), 0)]


def read_config_cache_segment(config_cache_path=None):
  """Config cache from session-start — static priors, treated as age 0."""
  if not config_cache_path or not os.path.exists(config_cache_path):
    return []
  try:
    with open(config_cache_path) as f:
      tc = json.load(f)
    text = ' '.join(tc.get('tags', []))
    if not text:
      return []
    return [(text, 0)]
  except (json.JSONDecodeError, IOError):
    return []


def _find_latest_jsonl_in_sessions_dir(cwd):
  """Find most recent .jsonl in ~/.claude/projects/<cwd-as-dashes>."""
  projects_dir = _project_sessions_dir(cwd)
  if not os.path.isdir(projects_dir):
    return None
  try:
    entries = [
      os.path.join(projects_dir, f)
      for f in os.listdir(projects_dir)
      if f.endswith('.jsonl')
    ]
  except OSError:
    return None
  if not entries:
    return None
  entries.sort(key=lambda p: os.path.getmtime(p), reverse=True)
  return entries[0]


def _is_session_file_fresh(path, now_ms, stale_max_min):
  """Check if session file mtime is within freshness window."""
  if path is None:
    return False
  try:
    session_age_min = (now_ms / 1000.0 - os.path.getmtime(path)) / 60.0
    return session_age_min <= stale_max_min
  except OSError:
    return False


def _extract_content_as_text(content):
  """Extract text from message content (string or list of parts)."""
  if isinstance(content, str):
    return content
  if isinstance(content, list):
    return ' '.join(
      part.get('text', '') for part in content
      if isinstance(part, dict) and part.get('type') == 'text'
    )
  return None


def _parse_transcript_line(line):
  """Parse one JSONL line into (role, text, ts_str) or None."""
  try:
    obj = json.loads(line.strip())
  except json.JSONDecodeError:
    return None
  kind = obj.get('type')
  if kind not in ('user', 'assistant'):
    return None
  msg = obj.get('message') or {}
  content = msg.get('content')
  text = _extract_content_as_text(content)
  if not text:
    return None
  ts_str = obj.get('timestamp')
  role = 'user' if kind == 'user' else 'assistant'
  return (role, text, ts_str)


def _extract_message_text(text, expected_role):
  """Process text based on role (e.g., strip fences from assistant)."""
  if expected_role == 'assistant':
    text = _strip_fenced_code(text)
  return text


def _compute_turn_age_min_from_iso(ts_str, now_ms):
  """Convert ISO timestamp to age in minutes."""
  if not ts_str:
    return 0.0
  try:
    from datetime import datetime
    turn_ts_ms = int(
      datetime.fromisoformat(ts_str.replace('Z', '+00:00')).timestamp() * 1000
    )
    return _age_min_from_timestamp_ms(turn_ts_ms, now_ms)
  except Exception:
    return 0.0


def _read_turns_from_jsonl(path, now_ms):
  """Read and parse turns from session JSONL file."""
  turns = []
  try:
    with open(path) as f:
      for line in f:
        result = _parse_transcript_line(line)
        if result is None:
          continue
        role, text, ts_str = result
        text = _extract_message_text(text, role)
        age_min = _compute_turn_age_min_from_iso(ts_str, now_ms)
        turns.append((text, age_min))
  except (IOError, PermissionError):
    return None
  return turns


def read_session_transcript_segments(cwd=None, turns_min=5, turns_max=10, stale_max_min=30, now_ms=None):
  """Orchestrator: find session, validate freshness, parse turns, segment."""
  if now_ms is None:
    now_ms = int(time.time() * 1000)
  cwd = cwd or os.getcwd()
  latest = _find_latest_jsonl_in_sessions_dir(cwd)
  if not _is_session_file_fresh(latest, now_ms, stale_max_min):
    return []
  turns = _read_turns_from_jsonl(latest, now_ms)
  if turns is None:
    return []
  return turns[-turns_max:]


def classify_domain(tag_set, domains_config):
  """Derive domain from extracted tags. Returns domain name or None."""
  min_matches = domains_config.get('min_tag_matches', 2)
  best_domain = None
  best_count = 0
  for domain_name, domain_def in domains_config['domains'].items():
    count = len(tag_set & set(domain_def['tags']))
    if count >= min_matches and count > best_count:
      best_count = count
      best_domain = domain_name
  return best_domain


def compute_freshness(signal_count, target=FRESHNESS_SIGNAL_COUNT_TARGET):
  """Freshness ∈ [0, 1] — session-window signal count, not wall-clock window."""
  if target <= 0:
    return 0.0
  return min(1.0, signal_count / float(target))


def _match_segments_to_tag_candidates(segments, matcher, source_weight, half_life):
  """Match segments, return dict {tag: {weight, age_min, source}}."""
  candidates = {}
  for text, age_min in segments:
    if not text:
      continue
    decayed = source_weight * math.exp(-age_min / half_life) if half_life > 0 else source_weight
    matched_tags = matcher.match(text)
    for tag in matched_tags:
      candidates[tag] = {
        'weight': decayed,
        'age_min': round(age_min, 3),
      }
  return candidates


def _merge_tag_weight_keep_max(accumulator, candidates, source_name):
  """Merge candidates into accumulator, keeping highest weight."""
  for tag, cand in candidates.items():
    prev = accumulator.get(tag)
    if prev is None or prev['weight'] < cand['weight']:
      accumulator[tag] = {
        'weight': cand['weight'],
        'source': source_name,
        'age_min': cand['age_min'],
      }


def _rank_and_limit_tags(tag_weights, max_tags):
  """Sort by weight, limit to max_tags."""
  sorted_tags = sorted(tag_weights.items(), key=lambda x: -x[1]['weight'])
  return sorted_tags[:max_tags]


def _shape_extract_output(sorted_tags, domain, freshness, signal_source_count):
  """Build output dict from ranked tags + metadata."""
  return {
    'weighted_tags': [
      {
        'tag': tag,
        'slug': tag,
        'weight': round(v['weight'], 4),
        'source': v['source'],
        'age_min': v['age_min'],
      }
      for tag, v in sorted_tags
    ],
    'domain': domain,
    'freshness': round(freshness, 3),
    'signal_source_count': signal_source_count,
  }


def extract(sources, patterns_config, sources_config, domains_config):
  """Orchestrator: match sources, rank tags, compute domain + freshness."""
  matcher = PatternMatcher(patterns_config)
  weights = sources_config['weights']
  max_tags = sources_config['limits'].get('max_output_tags', DEFAULT_MAX_OUTPUT_TAGS)
  half_life = float(sources_config.get('recency_decay_half_life_min', 10))
  tag_weights = {}
  signal_sources = set()
  for source_name, segments in sources:
    if not segments:
      continue
    source_weight = weights.get(source_name, 0.4)
    candidates = _match_segments_to_tag_candidates(segments, matcher, source_weight, half_life)
    if candidates:
      signal_sources.add(source_name)
      _merge_tag_weight_keep_max(tag_weights, candidates, source_name)
  sorted_tags = _rank_and_limit_tags(tag_weights, max_tags)
  tag_set = set(t[0] for t in sorted_tags)
  domain = classify_domain(tag_set, domains_config)
  freshness = compute_freshness(len(signal_sources))
  return _shape_extract_output(sorted_tags, domain, freshness, len(signal_sources))


def parse_cli_mode_and_args(argv):
  """Extract --mode flag and remaining args."""
  mode = 'conversation'
  args = list(argv[1:])
  if '--mode' in args:
    idx = args.index('--mode')
    mode = args[idx + 1]
    args = args[:idx] + args[idx + 2:]
  return mode, args


def run_conversation_mode(args, configs):
  """Conversation mode: extract tags from conversation history only."""
  history_path = args[0] if args else os.path.expanduser('~/.claude/history.jsonl')
  project_filter = args[1] if len(args) > 1 else None
  limits = configs['sources']['limits']
  segments = read_conversation_segments(
    history_path, project_filter, limits.get('max_conversation_entries', DEFAULT_MAX_CONVERSATION_ENTRIES)
  )
  matcher = PatternMatcher(configs['patterns'])
  found = set()
  for text, _ in segments:
    found |= matcher.match(text)
  result = list(found)[:limits.get('max_output_tags', DEFAULT_MAX_OUTPUT_TAGS)]
  print(json.dumps(result))


def _read_env_sidequest_vars():
  """Extract SIDEQUEST_* environment variables."""
  return {
    'diff': os.environ.get('SIDEQUEST_DIFF', ''),
    'branch': os.environ.get('SIDEQUEST_BRANCH', ''),
    'commit_msg': os.environ.get('SIDEQUEST_COMMIT_MSG', ''),
  }


def _collect_all_sources(history_path, project_filter, limits):
  """Gather all sources: conversation + transcript + diff + git + config."""
  conv_segs = read_conversation_segments(
    history_path, project_filter, limits.get('max_conversation_entries', DEFAULT_MAX_CONVERSATION_ENTRIES)
  )
  trans_segs = read_session_transcript_segments(cwd=project_filter or os.getcwd())
  env_vars = _read_env_sidequest_vars()
  return [
    ('conversation', conv_segs + trans_segs),
    ('diff', read_diff_segment(env_vars['diff'], limits.get('max_diff_bytes', DEFAULT_MAX_DIFF_BYTES))),
    ('git_metadata', read_git_metadata_segment(env_vars['branch'], env_vars['commit_msg'])),
    ('config', read_config_cache_segment(os.path.expanduser('~/.sidequest/tech-context.json'))),
  ]


def run_full_mode(args, configs):
  """Full mode: extract tags from all sources + compute domain."""
  history_path = args[0] if args else os.path.expanduser('~/.claude/history.jsonl')
  project_filter = args[1] if len(args) > 1 else None
  limits = configs['sources']['limits']
  sources = _collect_all_sources(history_path, project_filter, limits)
  transcript_segments = sources[0][1]  # ('conversation', ...)
  result = extract(sources, configs['patterns'], configs['sources'], configs['domains'])
  result['transcript_segment_count'] = len(transcript_segments)
  print(json.dumps(result))


def main():
  """Parse args, dispatch to mode handler."""
  mode, args = parse_cli_mode_and_args(sys.argv)
  configs = load_all_configs()
  if mode == 'conversation':
    run_conversation_mode(args, configs)
  elif mode == 'full':
    run_full_mode(args, configs)
  else:
    print(json.dumps({'weighted_tags': [], 'domain': None}))


if __name__ == '__main__':
  try:
    main()
  except Exception:
    print(json.dumps({'weighted_tags': [], 'domain': None}))
