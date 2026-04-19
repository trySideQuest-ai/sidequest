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


def load_config(name):
    """Load a JSON config file from the config/ directory."""
    config_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'config')
    path = os.path.join(config_dir, name)
    with open(path) as f:
        return json.load(f)


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


def _age_min_from_timestamp_ms(ts_ms, now_ms):
    if ts_ms is None or ts_ms <= 0:
        return 0
    return max(0, (now_ms - ts_ms) / 60000.0)


def read_conversation_segments(history_path, project_filter=None, max_entries=100, now_ms=None):
    """Read conversation as a list of (text, age_min) segments.

    Each history.jsonl entry becomes one segment. Age is computed from the
    entry's `timestamp` (ms since epoch); entries without a timestamp get 0.
    """
    if not history_path or not os.path.exists(history_path):
        return []
    if now_ms is None:
        now_ms = int(time.time() * 1000)

    entries = []
    try:
        with open(history_path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                    if project_filter and entry.get('project', '') != project_filter:
                        continue
                    entries.append(entry)
                except json.JSONDecodeError:
                    continue
    except (IOError, PermissionError):
        return []

    entries = entries[-max_entries:]

    segments = []
    for entry in entries:
        age_min = _age_min_from_timestamp_ms(entry.get('timestamp'), now_ms)
        text = entry.get('display', '')
        if text:
            segments.append((text, age_min))
        pasted = entry.get('pastedContents', {})
        if isinstance(pasted, dict):
            for paste in pasted.values():
                if isinstance(paste, dict) and paste.get('content'):
                    segments.append((paste['content'], age_min))

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


_FENCED_CODE_RE = re.compile(r'```.*?```', re.DOTALL)


def _strip_fenced_code(text):
    if not text:
        return ''
    return _FENCED_CODE_RE.sub(' ', text)


def _project_sessions_dir(cwd):
    """Map cwd '/Users/tomer/proj' → '~/.claude/projects/-Users-tomer-proj'."""
    normalized = os.path.abspath(cwd).replace('/', '-')
    return os.path.expanduser(os.path.join('~/.claude/projects', normalized))


def read_session_transcript_segments(
    cwd=None, turns_min=5, turns_max=10, stale_max_min=30, now_ms=None,
):
    """Return recent user+assistant turn pairs from the latest Claude Code JSONL.

    Path: ~/.claude/projects/<cwd-slashes-as-dashes>/*.jsonl (flat, no 'sessions/' subdir).
    Most-recent file by mtime; skipped if older than stale_max_min.
    Strips fenced code blocks from assistant text. Returns list of (text, age_min) segments.
    Empty list on any error or if no session exists.
    """
    if now_ms is None:
        now_ms = int(time.time() * 1000)
    cwd = cwd or os.getcwd()
    projects_dir = _project_sessions_dir(cwd)
    if not os.path.isdir(projects_dir):
        return []

    try:
        entries = [
            os.path.join(projects_dir, f)
            for f in os.listdir(projects_dir)
            if f.endswith('.jsonl')
        ]
    except OSError:
        return []

    if not entries:
        return []

    entries.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    latest = entries[0]

    session_age_min = (now_ms / 1000.0 - os.path.getmtime(latest)) / 60.0
    if session_age_min > stale_max_min:
        return []

    turns = []
    try:
        with open(latest) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                kind = obj.get('type')
                role = None
                text = ''
                ts_str = obj.get('timestamp')
                if kind == 'user':
                    msg = obj.get('message', {}) or {}
                    content = msg.get('content')
                    if isinstance(content, str):
                        text = content
                    elif isinstance(content, list):
                        text = ' '.join(
                            part.get('text', '') for part in content
                            if isinstance(part, dict) and part.get('type') == 'text'
                        )
                    role = 'user'
                elif kind == 'assistant':
                    msg = obj.get('message', {}) or {}
                    content = msg.get('content')
                    if isinstance(content, list):
                        text = ' '.join(
                            part.get('text', '') for part in content
                            if isinstance(part, dict) and part.get('type') == 'text'
                        )
                    role = 'assistant'
                if not role or not text:
                    continue
                if role == 'assistant':
                    text = _strip_fenced_code(text)
                turn_age_min = 0
                if ts_str:
                    try:
                        from datetime import datetime
                        turn_ts_ms = int(
                            datetime.fromisoformat(ts_str.replace('Z', '+00:00')).timestamp() * 1000
                        )
                        turn_age_min = _age_min_from_timestamp_ms(turn_ts_ms, now_ms)
                    except Exception:
                        turn_age_min = 0
                turns.append((role, text, turn_age_min))
    except (IOError, PermissionError):
        return []

    # Keep the last turns_max turns; clamp to at least turns_min recency-wise
    keep = turns[-turns_max:]
    if len(keep) < turns_min:
        # Not enough turns — still return what we have
        pass
    return [(text, age_min) for _role, text, age_min in keep]


def classify_intent(intents_config, transcript_text='', diff_text='', branch='', commit_msg=''):
    """Priority-ordered rule-based classifier → one of 12 intent_enum values."""
    haystack = ' '.join([transcript_text, diff_text]).lower()
    branch_lc = (branch or '').lower()
    commit_lc = (commit_msg or '').lower()

    for rule in intents_config.get('rules', []):
        intent = rule['intent']
        prefixes_commit = [p.lower() for p in rule.get('commit_msg_prefixes', [])]
        if prefixes_commit and any(commit_lc.startswith(p) for p in prefixes_commit):
            return intent
        prefixes_branch = [p.lower() for p in rule.get('branch_prefixes', [])]
        if prefixes_branch and any(branch_lc.startswith(p) for p in prefixes_branch):
            return intent
        keywords = [kw.lower() for kw in rule.get('keywords', [])]
        if keywords and any(kw in haystack for kw in keywords):
            return intent

    return intents_config.get('default', 'writing_feature')


FRESHNESS_SIGNAL_COUNT_TARGET = 4


def compute_freshness(signal_count, target=FRESHNESS_SIGNAL_COUNT_TARGET):
    """Freshness ∈ [0, 1] — session-window signal count, not wall-clock window."""
    if target <= 0:
        return 0.0
    return min(1.0, signal_count / float(target))


def extract(sources, patterns_config, sources_config, domains_config):
    """
    Core extraction pipeline:
    1. For each source, iterate (text, age_min) segments and match patterns.
    2. Per matched tag: candidate weight = base_weight × exp(-age_min / half_life).
    3. Keep max candidate per tag across sources/segments.
    4. Derive domain from the kept tag set.
    5. Compute freshness from count of sources that produced ≥1 tag.
    6. Return sorted weighted tags + domain + freshness.
    """
    matcher = PatternMatcher(patterns_config)
    weights = sources_config['weights']
    max_tags = sources_config['limits'].get('max_output_tags', 20)
    half_life = float(sources_config.get('recency_decay_half_life_min', 10))

    tag_weights = {}
    signal_sources = set()

    for source_name, segments in sources:
        if not segments:
            continue
        source_weight = weights.get(source_name, 0.4)
        source_contributed = False
        for text, age_min in segments:
            if not text:
                continue
            decayed = source_weight * math.exp(-age_min / half_life) if half_life > 0 else source_weight
            matched_tags = matcher.match(text)
            if matched_tags:
                source_contributed = True
            for tag in matched_tags:
                prev = tag_weights.get(tag)
                if prev is None or prev['weight'] < decayed:
                    tag_weights[tag] = {
                        'weight': decayed,
                        'source': source_name,
                        'age_min': round(age_min, 3),
                    }
        if source_contributed:
            signal_sources.add(source_name)

    sorted_tags = sorted(tag_weights.items(), key=lambda x: -x[1]['weight'])[:max_tags]

    tag_set = set(t[0] for t in sorted_tags)
    domain = classify_domain(tag_set, domains_config)
    freshness = compute_freshness(len(signal_sources))

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
        'signal_source_count': len(signal_sources),
    }


def main():
    mode = 'conversation'
    args = sys.argv[1:]

    if '--mode' in args:
        idx = args.index('--mode')
        mode = args[idx + 1]
        args = args[:idx] + args[idx + 2:]

    patterns_config = load_config('patterns.json')
    sources_config = load_config('sources.json')
    domains_config = load_config('domains.json')

    limits = sources_config['limits']

    if mode == 'conversation':
        history_path = args[0] if args else os.path.expanduser('~/.claude/history.jsonl')
        project_filter = args[1] if len(args) > 1 else None
        segments = read_conversation_segments(
            history_path, project_filter, limits.get('max_conversation_entries', 100)
        )
        matcher = PatternMatcher(patterns_config)
        found = set()
        for text, _ in segments:
            found |= matcher.match(text)
        print(json.dumps(list(found)[:limits.get('max_output_tags', 20)]))
        return

    if mode == 'full':
        history_path = args[0] if args else os.path.expanduser('~/.claude/history.jsonl')
        project_filter = args[1] if len(args) > 1 else None

        try:
            intents_config = load_config('intents.json')
        except (IOError, json.JSONDecodeError):
            intents_config = {'default': 'writing_feature', 'rules': []}

        conversation_segments = read_conversation_segments(
            history_path, project_filter, limits.get('max_conversation_entries', 100)
        )
        transcript_segments = read_session_transcript_segments(
            cwd=project_filter or os.getcwd()
        )
        diff_segments = read_diff_segment(
            os.environ.get('SIDEQUEST_DIFF', ''),
            limits.get('max_diff_bytes', 51200),
        )
        git_metadata_segments = read_git_metadata_segment(
            os.environ.get('SIDEQUEST_BRANCH', ''),
            os.environ.get('SIDEQUEST_COMMIT_MSG', ''),
        )
        config_cache_segments = read_config_cache_segment(
            os.path.expanduser('~/.sidequest/tech-context.json')
        )

        sources = [
            ('conversation', conversation_segments + transcript_segments),
            ('diff', diff_segments),
            ('git_metadata', git_metadata_segments),
            ('config', config_cache_segments),
        ]

        transcript_text = ' '.join(text for text, _ in transcript_segments)
        diff_text = os.environ.get('SIDEQUEST_DIFF', '') or ''
        intent_enum = classify_intent(
            intents_config,
            transcript_text=transcript_text,
            diff_text=diff_text,
            branch=os.environ.get('SIDEQUEST_BRANCH', ''),
            commit_msg=os.environ.get('SIDEQUEST_COMMIT_MSG', ''),
        )

        result = extract(sources, patterns_config, sources_config, domains_config)
        result['intent_enum'] = intent_enum
        result['transcript_segment_count'] = len(transcript_segments)
        print(json.dumps(result))
        return

    print(json.dumps({'weighted_tags': [], 'domain': None, 'intent_enum': 'writing_feature'}))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print(json.dumps({'weighted_tags': [], 'domain': None}))
