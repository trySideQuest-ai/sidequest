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
import os
import re
import sys


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
            # Patterns in config are fully self-contained — they include their own
            # word boundaries where needed. The matcher just joins and compiles.
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


def read_conversation(history_path, project_filter=None, max_entries=100):
    """Read conversation text from history.jsonl."""
    if not history_path or not os.path.exists(history_path):
        return ''

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
        return ''

    # Most recent entries only
    entries = entries[-max_entries:]

    parts = []
    for entry in entries:
        text = entry.get('display', '')
        if text:
            parts.append(text)
        # Include pasted content
        pasted = entry.get('pastedContents', {})
        if isinstance(pasted, dict):
            for paste in pasted.values():
                if isinstance(paste, dict) and paste.get('content'):
                    parts.append(paste['content'])

    return ' '.join(parts)


def read_diff(diff_text=None, max_bytes=51200):
    """Read diff content, capped at max_bytes."""
    if diff_text is None:
        return ''
    if len(diff_text) > max_bytes:
        diff_text = diff_text[:max_bytes]
    return diff_text


def read_git_metadata(branch=None, commit_msg=None):
    """Combine branch name and commit message into searchable text."""
    parts = []
    if branch:
        # Convert branch names like "feat/add-postgres-auth" into searchable tokens
        parts.append(branch.replace('/', ' ').replace('-', ' ').replace('_', ' '))
    if commit_msg:
        parts.append(commit_msg)
    return ' '.join(parts)


def read_config_cache(config_cache_path=None):
    """Read cached tech context tags from session-start."""
    if not config_cache_path or not os.path.exists(config_cache_path):
        return ''
    try:
        with open(config_cache_path) as f:
            tc = json.load(f)
        # Return tags as space-separated string for pattern matching
        return ' '.join(tc.get('tags', []))
    except (json.JSONDecodeError, IOError):
        return ''


def extract(sources, patterns_config, sources_config, domains_config):
    """
    Core extraction pipeline:
    1. For each source, match patterns and collect {tag: {weight, source}}
    2. Highest weight wins per tag
    3. Derive domain from tag set
    4. Return sorted weighted tags + domain
    """
    matcher = PatternMatcher(patterns_config)
    weights = sources_config['weights']
    max_tags = sources_config['limits'].get('max_output_tags', 20)

    tag_weights = {}

    for source_name, text in sources:
        if not text:
            continue
        source_weight = weights.get(source_name, 0.4)
        matched_tags = matcher.match(text)

        for tag in matched_tags:
            if tag not in tag_weights or tag_weights[tag]['weight'] < source_weight:
                tag_weights[tag] = {'weight': source_weight, 'source': source_name}

    # Sort by weight descending, limit
    sorted_tags = sorted(tag_weights.items(), key=lambda x: -x[1]['weight'])[:max_tags]

    tag_set = set(t[0] for t in sorted_tags)
    domain = classify_domain(tag_set, domains_config)

    return {
        'weighted_tags': [{'tag': t, 'weight': v['weight'], 'source': v['source']} for t, v in sorted_tags],
        'domain': domain,
    }


def main():
    mode = 'conversation'  # Default: legacy mode for backward compat
    args = sys.argv[1:]

    # Parse --mode flag (stop-hook passes --mode full)
    if '--mode' in args:
        idx = args.index('--mode')
        mode = args[idx + 1]
        args = args[:idx] + args[idx + 2:]

    # Load configs
    patterns_config = load_config('patterns.json')
    sources_config = load_config('sources.json')
    domains_config = load_config('domains.json')

    limits = sources_config['limits']

    if mode == 'conversation':
        # Legacy mode: just conversation, returns flat tag array for backward compat
        history_path = args[0] if args else os.path.expanduser('~/.claude/history.jsonl')
        project_filter = args[1] if len(args) > 1 else None
        text = read_conversation(history_path, project_filter, limits.get('max_conversation_entries', 100))
        matcher = PatternMatcher(patterns_config)
        tags = list(matcher.match(text))[:limits.get('max_output_tags', 20)]
        print(json.dumps(tags))
        return

    if mode == 'full':
        # Full extraction: all sources
        history_path = args[0] if args else os.path.expanduser('~/.claude/history.jsonl')
        project_filter = args[1] if len(args) > 1 else None

        conversation_text = read_conversation(
            history_path, project_filter, limits.get('max_conversation_entries', 100)
        )
        diff_text = read_diff(
            os.environ.get('SIDEQUEST_DIFF', ''),
            limits.get('max_diff_bytes', 51200)
        )
        git_metadata_text = read_git_metadata(
            os.environ.get('SIDEQUEST_BRANCH', ''),
            os.environ.get('SIDEQUEST_COMMIT_MSG', '')
        )
        config_cache_text = read_config_cache(
            os.path.expanduser('~/.sidequest/tech-context.json')
        )

        sources = [
            ('conversation', conversation_text),
            ('diff', diff_text),
            ('git_metadata', git_metadata_text),
            ('config', config_cache_text),
        ]

        result = extract(sources, patterns_config, sources_config, domains_config)
        print(json.dumps(result))
        return

    # Unknown mode — empty output
    print(json.dumps({'weighted_tags': [], 'domain': None}))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Always output valid JSON, never crash
        print(json.dumps({'weighted_tags': [], 'domain': None}))
