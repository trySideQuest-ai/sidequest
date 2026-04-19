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


def extract(sources, patterns_config, sources_config, domains_config):
    """
    Core extraction pipeline:
    1. For each source, iterate (text, age_min) segments and match patterns.
    2. Per matched tag: candidate weight = base_weight × exp(-age_min / half_life).
    3. Keep max candidate per tag across sources/segments.
    4. Derive domain from the kept tag set.
    5. Return sorted weighted tags + domain.
    """
    matcher = PatternMatcher(patterns_config)
    weights = sources_config['weights']
    max_tags = sources_config['limits'].get('max_output_tags', 20)
    half_life = float(sources_config.get('recency_decay_half_life_min', 10))

    tag_weights = {}

    for source_name, segments in sources:
        if not segments:
            continue
        source_weight = weights.get(source_name, 0.4)
        for text, age_min in segments:
            if not text:
                continue
            decayed = source_weight * math.exp(-age_min / half_life) if half_life > 0 else source_weight
            matched_tags = matcher.match(text)
            for tag in matched_tags:
                prev = tag_weights.get(tag)
                if prev is None or prev['weight'] < decayed:
                    tag_weights[tag] = {
                        'weight': decayed,
                        'source': source_name,
                        'age_min': round(age_min, 3),
                    }

    sorted_tags = sorted(tag_weights.items(), key=lambda x: -x[1]['weight'])[:max_tags]

    tag_set = set(t[0] for t in sorted_tags)
    domain = classify_domain(tag_set, domains_config)

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

        conversation_segments = read_conversation_segments(
            history_path, project_filter, limits.get('max_conversation_entries', 100)
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
            ('conversation', conversation_segments),
            ('diff', diff_segments),
            ('git_metadata', git_metadata_segments),
            ('config', config_cache_segments),
        ]

        result = extract(sources, patterns_config, sources_config, domains_config)
        print(json.dumps(result))
        return

    print(json.dumps({'weighted_tags': [], 'domain': None}))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print(json.dumps({'weighted_tags': [], 'domain': None}))
