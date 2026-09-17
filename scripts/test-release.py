#!/usr/bin/env python3
"""Offline regression checks for release rejection paths."""
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
import zipfile


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


package = module("package", "package.py")
verify = module("verify_release", "verify-release.py")
publish = module("publish_release", "publish-release.py")


class ReleaseChecks(unittest.TestCase):
    def test_reads_marketing_version_from_project_spec(self):
        self.assertEqual(package.base_version('settings:\n  base:\n    MARKETING_VERSION: "2.3.4"\n'), "2.3.4")
        self.assertEqual(package.base_version("MARKETING_VERSION: 2.3.4\n"), "2.3.4")
        for spec in ['MARKETING_VERSION: "1.0"\n', "", 'MARKETING_VERSION: "1.0.0"\nMARKETING_VERSION: "1.0.1"\n',
                     '# MARKETING_VERSION: "1.0.0"\n']:
            with self.assertRaises(ValueError):
                package.base_version(spec)

    def test_repository_spec_declares_a_three_part_version(self):
        version = package.base_version((package.PROJECT_DIR / "project.yml").read_text())
        self.assertRegex(version, r"^\d+\.\d+\.\d+$")

    def test_rejects_development_identity(self):
        listing = '1) ' + 'A' * 40 + ' "Apple Development: Example (0123456789)"'
        with self.assertRaises(ValueError):
            package.developer_identity('A' * 40, listing)

    def test_selects_exact_developer_id_identity(self):
        name = 'Developer ID Application: Example (0123456789)'
        listing = '1) ' + 'A' * 40 + ' "' + name + '"'
        self.assertEqual(package.developer_identity(name, listing), ('A' * 40, name, '0123456789'))
        self.assertEqual(package.developer_identity('a' * 40, listing)[0], 'A' * 40)
        with self.assertRaises(ValueError):
            package.developer_identity('Example', listing)

    def test_rejects_ambiguous_identity(self):
        name = 'Developer ID Application: Example (0123456789)'
        listing = '\n'.join(str(i) + ') ' + c * 40 + ' "' + name + '"' for i, c in [(1, 'A'), (2, 'B')])
        with self.assertRaises(ValueError):
            package.developer_identity(name, listing)

    def test_requires_accepted_notary_status_and_identifier(self):
        submission = {'id': '01234567-89ab-cdef-0123-456789abcdef', 'status': 'Accepted'}
        self.assertEqual(package.accepted_submission(submission), submission)
        for value in [None, {}, dict(submission, status='Invalid'), dict(submission, status='In Progress'),
                      dict(submission, id=''), dict(submission, id=None)]:
            with self.assertRaises(ValueError):
                package.accepted_submission(value)

    def test_app_store_export_uploads_without_renumbering(self):
        options = package.export_options('0123456789')
        self.assertEqual(options['method'], 'app-store-connect')
        self.assertEqual(options['destination'], 'upload')
        self.assertEqual(options['teamID'], '0123456789')
        self.assertIs(options['manageAppVersionAndBuildNumber'], False)

    def test_manifest_detects_altered_download(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            asset = directory / 'Sample.dmg'
            asset.write_bytes(b'original')
            manifest = directory / 'checksums.txt'
            manifest.write_text(verify.sha256(asset) + '  Sample.dmg\n')
            self.assertIn('Sample.dmg', verify.verify_checksums(directory, manifest))
            asset.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
                verify.verify_checksums(directory, manifest)

    def test_manifest_rejects_escape_duplicate_and_symlink(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            asset = directory / 'Sample.dmg'
            asset.write_bytes(b'original')
            line = verify.sha256(asset) + '  Sample.dmg\n'
            manifest = directory / 'checksums.txt'
            for contents in [line + line, line.replace('Sample.dmg', '../Sample.dmg'), '']:
                manifest.write_text(contents)
                with self.assertRaises(ValueError):
                    verify.verify_checksums(directory, manifest)
            (directory / 'Link.dmg').symlink_to(asset)
            manifest.write_text(line.replace('Sample.dmg', 'Link.dmg'))
            with self.assertRaises(ValueError):
                verify.verify_checksums(directory, manifest)

    def test_zip_rejects_unsafe_paths_before_extraction(self):
        for name in ['../escape', '/absolute', 'Tudor PCB.app/../../escape', 'Tudor PCB.app/..\\escape',
                     'Other.app/file', 'Tudor PCB.app.dSYM/Contents/Info.plist']:
            stream = io.BytesIO()
            with zipfile.ZipFile(stream, 'w') as archive:
                archive.writestr(name, b'data')
            with zipfile.ZipFile(stream) as archive:
                with self.assertRaises(ValueError):
                    verify.check_zip_paths(archive, 'Tudor PCB.app')
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, 'w') as archive:
            archive.writestr('Tudor PCB.app/Contents/Info.plist', b'data')
            archive.writestr('__MACOSX/Tudor PCB.app/._Info.plist', b'data')
        with zipfile.ZipFile(stream) as archive:
            verify.check_zip_paths(archive, 'Tudor PCB.app')

    def test_zip_rejects_symlinks_before_extraction(self):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, 'w') as archive:
            info = zipfile.ZipInfo('Tudor PCB.app/Contents/link')
            info.create_system = 3
            info.external_attr = 0o120777 << 16
            archive.writestr(info, '/outside')
        with zipfile.ZipFile(stream) as archive:
            with self.assertRaises(ValueError):
                verify.check_zip_paths(archive, 'Tudor PCB.app')

    def test_draft_release_is_found_through_the_listing(self):
        draft = {'tag_name': 'v1.0.0', 'draft': True, 'assets': []}
        published = {'tag_name': 'v0.9.0', 'draft': False, 'assets': []}
        self.assertEqual(publish.select_release([published, draft], 'v1.0.0'), draft)
        self.assertEqual(publish.select_release([published, draft], 'v0.9.0'), published)
        self.assertIsNone(publish.select_release([published], 'v1.0.0'))
        self.assertIsNone(publish.select_release([], 'v1.0.0'))
        with self.assertRaises(ValueError):
            publish.select_release([draft, dict(draft)], 'v1.0.0')

    def test_dsym_identity_uses_every_slice(self):
        listing = ('UUID: 7F4FC7AE-6C19-3366-ABBD-6D42EF8367FD (x86_64) /path/Tudor PCB\n'
                   'UUID: 475F0134-541B-36D6-9084-D3E95F53CF49 (arm64) /path/Tudor PCB\n')
        self.assertEqual(verify.parse_uuids(listing), {('7F4FC7AE-6C19-3366-ABBD-6D42EF8367FD', 'x86_64'),
                                                       ('475F0134-541B-36D6-9084-D3E95F53CF49', 'arm64')})
        self.assertNotEqual(verify.parse_uuids(listing), verify.parse_uuids(listing.splitlines()[0] + '\n'))
        with self.assertRaises(ValueError):
            verify.parse_uuids('')


if __name__ == '__main__':
    unittest.main()
