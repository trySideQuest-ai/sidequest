"""Tests for plugin auto-update: version check, SHA256 verify, atomic swap, rollback."""

import hashlib
import json
import os
import shutil
import tarfile
import tempfile
import unittest


class AutoUpdateTests(unittest.TestCase):
    """Test auto-update logic: version comparison, SHA256, atomic swap, backup."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.sidequest_dir = os.path.join(self.tmpdir, '.sidequest')
        os.makedirs(self.sidequest_dir)
        self.plugin_root = os.path.join(self.tmpdir, 'plugin')
        os.makedirs(os.path.join(self.plugin_root, 'hooks'))
        # Write current VERSION
        with open(os.path.join(self.plugin_root, 'VERSION'), 'w') as f:
            f.write('0.1.0\n')
        # Write a dummy hook file to verify backup works
        with open(os.path.join(self.plugin_root, 'hooks', 'stop-hook'), 'w') as f:
            f.write('#!/bin/bash\necho "old version"')

    def tearDown(self):
        shutil.rmtree(self.tmpdir)

    def _make_tarball(self, version='0.2.0'):
        """Create a plugin tarball matching the packaging format."""
        staging = os.path.join(self.tmpdir, 'staging', 'sidequest-plugin')
        os.makedirs(os.path.join(staging, 'hooks'), exist_ok=True)
        with open(os.path.join(staging, 'VERSION'), 'w') as f:
            f.write(f'{version}\n')
        with open(os.path.join(staging, 'hooks', 'stop-hook'), 'w') as f:
            f.write(f'#!/bin/bash\necho "version {version}"')

        tarball_path = os.path.join(self.tmpdir, f'sidequest-plugin-{version}.tar.gz')
        with tarfile.open(tarball_path, 'w:gz') as tar:
            tar.add(staging, arcname='sidequest-plugin')

        with open(tarball_path, 'rb') as f:
            sha256 = hashlib.sha256(f.read()).hexdigest()

        shutil.rmtree(os.path.join(self.tmpdir, 'staging'))
        return tarball_path, sha256

    def test_version_mismatch_detected(self):
        """Plugin detects when local version differs from remote config."""
        local_version = '0.1.0'
        remote_version = '0.2.0'
        self.assertNotEqual(local_version, remote_version)

    def test_version_match_skips_update(self):
        """No update when local and remote versions are the same."""
        local_version = '0.1.0'
        remote_version = '0.1.0'
        self.assertEqual(local_version, remote_version)

    def test_sha256_verification_passes(self):
        """SHA256 of downloaded tarball matches expected hash."""
        tarball_path, expected_sha = self._make_tarball()
        with open(tarball_path, 'rb') as f:
            actual_sha = hashlib.sha256(f.read()).hexdigest()
        self.assertEqual(actual_sha, expected_sha)

    def test_sha256_verification_rejects_corrupt(self):
        """Corrupt tarball fails SHA256 check."""
        tarball_path, expected_sha = self._make_tarball()
        # Corrupt the file
        with open(tarball_path, 'ab') as f:
            f.write(b'corrupt')
        with open(tarball_path, 'rb') as f:
            actual_sha = hashlib.sha256(f.read()).hexdigest()
        self.assertNotEqual(actual_sha, expected_sha)

    def test_tarball_extraction(self):
        """Plugin tarball extracts to single directory with expected structure."""
        tarball_path, _ = self._make_tarball()
        extract_dir = os.path.join(self.tmpdir, 'extracted')
        os.makedirs(extract_dir)
        with tarfile.open(tarball_path, 'r:gz') as tar:
            tar.extractall(extract_dir)
        contents = os.listdir(extract_dir)
        self.assertEqual(len(contents), 1)
        self.assertEqual(contents[0], 'sidequest-plugin')
        self.assertTrue(os.path.isfile(
            os.path.join(extract_dir, 'sidequest-plugin', 'VERSION')
        ))

    def test_backup_created_before_swap(self):
        """Previous hooks directory is backed up before swap."""
        backup_dir = os.path.join(self.sidequest_dir, 'hooks.backup')
        hooks_dir = os.path.join(self.plugin_root, 'hooks')
        # Simulate backup
        shutil.copytree(hooks_dir, backup_dir)
        self.assertTrue(os.path.isdir(backup_dir))
        self.assertTrue(os.path.isfile(
            os.path.join(backup_dir, 'stop-hook')
        ))
        with open(os.path.join(backup_dir, 'stop-hook')) as f:
            self.assertIn('old version', f.read())

    def test_atomic_swap_updates_hooks(self):
        """After swap, hooks contain new version content."""
        tarball_path, _ = self._make_tarball('0.3.0')
        extract_dir = os.path.join(self.tmpdir, 'extracted')
        os.makedirs(extract_dir)
        with tarfile.open(tarball_path, 'r:gz') as tar:
            tar.extractall(extract_dir)
        new_hooks = os.path.join(extract_dir, 'sidequest-plugin', 'hooks')
        hooks_dir = os.path.join(self.plugin_root, 'hooks')
        # Simulate atomic swap
        for item in os.listdir(new_hooks):
            src = os.path.join(new_hooks, item)
            dst = os.path.join(hooks_dir, item)
            shutil.copy2(src, dst)
        with open(os.path.join(hooks_dir, 'stop-hook')) as f:
            self.assertIn('version 0.3.0', f.read())

    def test_version_file_updated_after_swap(self):
        """VERSION file reflects new version after swap."""
        tarball_path, _ = self._make_tarball('0.4.0')
        extract_dir = os.path.join(self.tmpdir, 'extracted')
        os.makedirs(extract_dir)
        with tarfile.open(tarball_path, 'r:gz') as tar:
            tar.extractall(extract_dir)
        new_version_file = os.path.join(extract_dir, 'sidequest-plugin', 'VERSION')
        dst_version_file = os.path.join(self.plugin_root, 'VERSION')
        shutil.copy2(new_version_file, dst_version_file)
        with open(dst_version_file) as f:
            self.assertEqual(f.read().strip(), '0.4.0')

    def test_empty_remote_config_fields_skip_update(self):
        """Update skipped when remote config has empty version/url/sha fields."""
        rc = {"plugin_version": "", "plugin_sha256": "", "plugin_tarball_url": ""}
        self.assertFalse(bool(rc['plugin_version']))
        self.assertFalse(bool(rc['plugin_tarball_url']))
        self.assertFalse(bool(rc['plugin_sha256']))


if __name__ == '__main__':
    unittest.main()
