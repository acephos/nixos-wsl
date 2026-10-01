"""Real temporary Git repositories; command fixtures never activate a host system."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        (self.repo / 'flake.nix').write_text('fixture')
        for args in [('init',), ('config', 'user.name', 'Fixture'), ('config', 'user.email', 'fixture@example.invalid'), ('add', '.'), ('commit', '-m', 'initial')]:
            self.git(*args)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin)+':'+os.environ['PATH'], NIXOS_FLAKE=str(self.repo), NIXOS_AUTO_PUSH='0')
        self.command('sudo', 'exec "$@"')
        self.command('nixos-rebuild', 'exit "${FIXTURE_RC:-0}"')
        self.command('nix', "printf '/nix/store/fixture-system\\n'")
        self.command('readlink', "printf '%s\\n' \"${FIXTURE_CLOSURE:-/nix/store/fixture-system}\"")
        self.command('nixos-version', "printf 'fixture\\n'")
        self.command('nix-env', "printf '1 (current)\\n'")
    def command(self, name, body):
        p = self.bin / name
        p.write_text('#!/bin/bash\n'+body+'\n')
        p.chmod(0o755)
    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], stderr=subprocess.DEVNULL, text=True).strip()
    def run_script(self, name, *args, **extra):
        return subprocess.run(['bash', str(ROOT/'scripts'/name), *args], env=dict(self.env, **extra), capture_output=True, text=True)
    def test_snapshots_never_claim_verified_build(self):
        result=self.run_script('checkpoint.sh', 'fixture snapshot')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git('tag'), 'source-snapshot')
    def test_nonzero_and_profile_mismatch_never_tag(self):
        initial=self.git('rev-parse','HEAD')
        for code in ['1','4']:
            result=self.run_script('rebuild.sh', FIXTURE_RC=code)
            self.assertEqual(result.returncode, int(code))
            self.assertEqual(self.git('tag'), '')
            self.assertEqual(self.git('rev-parse','HEAD'), initial)
        result=self.run_script('rebuild.sh', FIXTURE_CLOSURE='/nix/store/wrong')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.git('tag'), '')
    def test_success_tags_exact_commit_with_closure_receipt(self):
        (self.repo/'flake.nix').write_text('changed fixture')
        result=self.run_script('rebuild.sh')
        self.assertEqual(result.returncode,0,result.stderr)
        tags=self.git('tag').splitlines()
        self.assertIn('build-verified',tags)
        receipt=next(x for x in tags if x.startswith('build-verified-'))
        self.assertEqual(self.git('rev-parse','build-verified^{commit}'),self.git('rev-parse','HEAD'))
        self.assertIn('closure=/nix/store/fixture-system',self.git('tag','-n99',receipt))
    def test_no_commit_dirty_and_midbuild_changes_fail_closed(self):
        (self.repo/'flake.nix').write_text('dirty')
        self.assertNotEqual(self.run_script('rebuild.sh','--no-commit').returncode,0)
        self.assertEqual(self.git('tag'),'')
        self.command('nixos-rebuild','printf changed-again >> flake.nix; exit 0')
        self.assertNotEqual(self.run_script('rebuild.sh').returncode,0)
        self.assertEqual(self.git('tag'),'')
    @unittest.skipUnless(shutil.which('jq'), 'jq unavailable')
    def test_locked_plan_uses_exact_recorded_versions(self):
        lock={'piPackage':'@fixture/pi','pi':'1.2.3','ompPackage':'@fixture/omp','omp':'4.5.6'}
        path=self.repo/'agents.lock.json'
        path.write_text(json.dumps(lock))
        result=self.run_script('update-agents.sh','--locked','--plan')
        self.assertEqual(result.returncode,0,result.stderr)
        plan=json.loads(result.stdout)
        self.assertEqual(plan['pi'],'@fixture/pi@1.2.3')
        self.assertEqual(plan['omp'],'@fixture/omp@4.5.6')
        self.assertFalse(plan['flake_update'])
        self.assertFalse(plan['extension_update'])
        self.assertEqual(json.loads(path.read_text()),lock)
        lock['pi']='latest'
        path.write_text(json.dumps(lock))
        self.assertNotEqual(self.run_script('update-agents.sh','--locked','--plan').returncode,0)

    def test_test_activation_does_not_tag(self):
        result=self.run_script('rebuild.sh','test')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(self.git('tag'),'')

if __name__ == '__main__': unittest.main()
