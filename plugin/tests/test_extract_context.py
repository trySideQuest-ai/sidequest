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

    def test_extracts_database_tags(self):
        entries = [
            make_entry('help me fix my PostgreSQL query'),
            make_entry('the pg_dump command is failing'),
        ]
        tags = run_extractor(entries)
        self.assertIn('postgresql', tags)

    def test_extracts_framework_tags(self):
        entries = [
            make_entry('how do I use useState in React'),
            make_entry('my Next.js app is not building'),
        ]
        tags = run_extractor(entries)
        self.assertIn('react', tags)
        self.assertIn('nextjs', tags)

    def test_extracts_language_tags(self):
        entries = [
            make_entry('write a Python script to parse CSV'),
            make_entry('fix the typescript compilation error'),
        ]
        tags = run_extractor(entries)
        self.assertIn('python', tags)
        self.assertIn('typescript', tags)

    def test_extracts_devops_tags(self):
        entries = [
            make_entry('my docker container keeps crashing'),
            make_entry('update the kubernetes deployment'),
        ]
        tags = run_extractor(entries)
        self.assertIn('docker', tags)
        self.assertIn('kubernetes', tags)

    def test_extracts_cloud_tags(self):
        entries = [
            make_entry('deploy to AWS Lambda'),
            make_entry('configure the S3 bucket'),
        ]
        tags = run_extractor(entries)
        self.assertIn('aws', tags)

    def test_extracts_multiple_tags_from_single_message(self):
        entries = [
            make_entry('set up a React app with PostgreSQL and Docker'),
        ]
        tags = run_extractor(entries)
        self.assertIn('react', tags)
        self.assertIn('postgresql', tags)
        self.assertIn('docker', tags)

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

    def test_case_insensitive_matching(self):
        entries = [
            make_entry('using DOCKER and PostgreSQL'),
        ]
        tags = run_extractor(entries)
        self.assertIn('docker', tags)
        self.assertIn('postgresql', tags)

    # Concept-level tag tests (Phase 21)

    def test_extracts_email_tags(self):
        entries = [
            make_entry('set up SendGrid for transactional emails'),
            make_entry('using Resend API to send email templates'),
            make_entry('configure SMTP mailer for notifications'),
            make_entry('nodemailer for email dispatch'),
        ]
        tags = run_extractor(entries)
        self.assertIn('email', tags)

    def test_extracts_email_variants(self):
        entries = [
            make_entry('postmark is our email service'),
        ]
        tags = run_extractor(entries)
        self.assertIn('email', tags)

    def test_extracts_scheduling_tags(self):
        entries = [
            make_entry('set up a cron job to run daily'),
            make_entry('use a scheduler for periodic tasks'),
            make_entry('inngest for background scheduling'),
        ]
        tags = run_extractor(entries)
        self.assertIn('scheduling', tags)

    def test_extracts_scheduling_variants(self):
        entries = [
            make_entry('bull queue for delayed jobs'),
            make_entry('node-schedule for interval tasks'),
            make_entry('temporal workflow orchestration'),
        ]
        tags = run_extractor(entries)
        self.assertIn('scheduling', tags)

    def test_extracts_feature_flags_tags(self):
        entries = [
            make_entry('add a feature flag to enable new UI'),
            make_entry('launch darkly for feature toggles'),
            make_entry('use unleash for experiment rollout'),
        ]
        tags = run_extractor(entries)
        self.assertIn('feature_flags', tags)

    def test_extracts_feature_flags_variants(self):
        entries = [
            make_entry('statsig for gradual rollout'),
            make_entry('experiment flags for A/B testing'),
        ]
        tags = run_extractor(entries)
        self.assertIn('feature_flags', tags)

    def test_extracts_background_jobs_tags(self):
        entries = [
            make_entry('worker process for async tasks'),
            make_entry('sidekiq job queue implementation'),
            make_entry('celery for background jobs in Python'),
        ]
        tags = run_extractor(entries)
        self.assertIn('background_jobs', tags)

    def test_extracts_background_jobs_variants(self):
        entries = [
            make_entry('resque for job processing'),
            make_entry('bull for async job handling'),
            make_entry('background task processor implementation'),
        ]
        tags = run_extractor(entries)
        self.assertIn('background_jobs', tags)

    def test_extracts_secrets_management_tags(self):
        entries = [
            make_entry('use HashiCorp Vault for secrets'),
            make_entry('infisical for secret management'),
            make_entry('dotenv for environment variables'),
        ]
        tags = run_extractor(entries)
        self.assertIn('secrets_management', tags)

    def test_extracts_secrets_management_variants(self):
        entries = [
            make_entry('api key management best practices'),
            make_entry('secrets manager configuration'),
            make_entry('store database credentials securely'),
        ]
        tags = run_extractor(entries)
        self.assertIn('secrets_management', tags)

    def test_extracts_link_management_tags(self):
        entries = [
            make_entry('implement a URL shortener service'),
            make_entry('bitly integration for short links'),
            make_entry('dub for link tracking analytics'),
        ]
        tags = run_extractor(entries)
        self.assertIn('link_management', tags)

    def test_extracts_link_management_variants(self):
        entries = [
            make_entry('rebrandly for custom short URLs'),
            make_entry('link tracking for campaign metrics'),
            make_entry('redirect URL management system'),
        ]
        tags = run_extractor(entries)
        self.assertIn('link_management', tags)

    def test_extracts_notifications_tags(self):
        entries = [
            make_entry('add push notifications to the app'),
            make_entry('knock for notification service'),
            make_entry('novu notification hub setup'),
        ]
        tags = run_extractor(entries)
        self.assertIn('notifications', tags)

    def test_extracts_notifications_variants(self):
        entries = [
            make_entry('onesignal for mobile push notifications'),
            make_entry('alert system for critical events'),
            make_entry('slack message API integration'),
            make_entry('webhook notification delivery'),
        ]
        tags = run_extractor(entries)
        self.assertIn('notifications', tags)

    def test_extracts_multiple_concepts(self):
        """Verify multiple concept tags can be extracted from a single conversation."""
        entries = [
            make_entry('set up SendGrid for emails and use Temporal for scheduling'),
            make_entry('implement feature flags with Unleash and background jobs with Celery'),
            make_entry('vault for secrets and bitly for short links'),
        ]
        tags = run_extractor(entries)
        self.assertIn('email', tags)
        self.assertIn('scheduling', tags)
        self.assertIn('feature_flags', tags)
        self.assertIn('background_jobs', tags)
        self.assertIn('secrets_management', tags)
        self.assertIn('link_management', tags)

    def test_concept_tags_with_tool_tags(self):
        """Verify concept tags coexist with tool tags without conflict."""
        entries = [
            make_entry('using React with TypeScript, need SendGrid for emails and PostGres'),
        ]
        tags = run_extractor(entries)
        self.assertIn('react', tags)
        self.assertIn('typescript', tags)
        self.assertIn('postgresql', tags)
        self.assertIn('email', tags)

    def test_all_seven_concepts_detected(self):
        """Integration test: verify all 7 concept tags can be detected."""
        entries = [
            make_entry('sendgrid email setup'),
            make_entry('cron scheduler config'),
            make_entry('feature flag rollout'),
            make_entry('celery background jobs'),
            make_entry('vault secrets manager'),
            make_entry('bitly link shortener'),
            make_entry('push notifications'),
        ]
        tags = run_extractor(entries)
        concepts = ['email', 'scheduling', 'feature_flags', 'background_jobs',
                   'secrets_management', 'link_management', 'notifications']
        for concept in concepts:
            self.assertIn(concept, tags, f'Concept "{concept}" not detected')


if __name__ == '__main__':
    unittest.main()
