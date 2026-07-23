import importlib.util
import json
import os
import pathlib
import shutil
import tempfile
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).with_name("hermes-approval.py")
SPEC = importlib.util.spec_from_file_location("hermes_approval", MODULE_PATH)
approval = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(approval)
SHELL = shutil.which("bash")


class RequestValidationTests(unittest.TestCase):
    def setUp(self):
        self.sources = {
            "cornn-flaek": {
                "repository": "jeiang/.dotfiles",
                "worktree": "/workspace/cornn-flaek",
            }
        }

    def test_command_request_is_hashed_and_bounded(self):
        request = approval.new_request(
            "command",
            "run validation",
            command="just check",
            cwd="cornn-flaek",
            timeout=600,
        )
        identifier, kind = approval.validate_request(request, self.sources)
        self.assertEqual(identifier, request["id"])
        self.assertEqual(kind, "command")

        request["command"] = "x" * (approval.MAX_COMMAND_LENGTH + 1)
        request["request_hash"] = approval.request_hash(request)
        with self.assertRaisesRegex(ValueError, "exceeds"):
            approval.validate_request(request, self.sources)

    def test_request_rejects_escape_and_unapproved_service_action(self):
        command = approval.new_request(
            "command",
            "escape",
            command="pwd",
            cwd="../outside",
            timeout=1,
        )
        with self.assertRaisesRegex(ValueError, "inside the workspace"):
            approval.validate_request(command, self.sources)

        service = approval.new_request(
            "service",
            "not allowed",
            action="stop",
            unit="hermes-approval-broker.service",
        )
        with self.assertRaisesRegex(ValueError, "outside policy"):
            approval.validate_request(service, self.sources)

        service["action"] = "status"
        service["request_hash"] = approval.request_hash(service)
        self.assertEqual(
            approval.validate_request(service, self.sources)[1],
            "service",
        )

    def test_publication_uses_a_named_source_and_exact_commit(self):
        request = approval.new_request(
            "publication",
            "publish changes",
            source="cornn-flaek",
            branch="codex/hermes",
            commit="a" * 40,
            title="feat: test",
            body="",
        )
        self.assertEqual(
            approval.validate_request(request, self.sources)[1],
            "publication",
        )
        request["source"] = "other"
        request["request_hash"] = approval.request_hash(request)
        with self.assertRaisesRegex(ValueError, "outside policy"):
            approval.validate_request(request, self.sources)


class FileBoundaryTests(unittest.TestCase):
    def test_safe_reader_rejects_symlinks_and_wrong_modes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            target = root / "target.json"
            target.write_text("{}")
            target.chmod(0o640)
            link = root / "link.json"
            link.symlink_to(target)
            with self.assertRaises(OSError):
                approval.safe_json_file(link, os.getuid(), 0o640)

            target.chmod(0o660)
            with self.assertRaisesRegex(ValueError, "mode"):
                approval.safe_json_file(target, os.getuid(), 0o640)

    def test_submission_is_exclusive(self):
        with tempfile.TemporaryDirectory() as directory:
            request = approval.new_request(
                "command",
                "test",
                command="true",
                cwd=".",
                timeout=1,
            )
            approval.submit_request(directory, request)
            with self.assertRaises(FileExistsError):
                approval.submit_request(directory, request)


class CommandExecutionTests(unittest.TestCase):
    def test_output_is_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            result = approval.run_bounded(
                "head -c 70000 /dev/zero; head -c 70000 /dev/zero >&2",
                directory,
                5,
                shell=SHELL,
            )
        self.assertEqual(result["state"], "completed")
        self.assertEqual(len(result["stdout"]), approval.MAX_OUTPUT)
        self.assertEqual(len(result["stderr"]), approval.MAX_OUTPUT)
        self.assertTrue(result["stdout_truncated"])
        self.assertTrue(result["stderr_truncated"])

    def test_timeout_and_cancel_terminate_the_process_group(self):
        with tempfile.TemporaryDirectory() as directory:
            timeout = approval.run_bounded("sleep 5", directory, 1, shell=SHELL)
            self.assertEqual(timeout["state"], "timed_out")

            cancel = pathlib.Path(directory) / "cancel"
            cancel.touch()
            cancelled = approval.run_bounded(
                "sleep 5",
                directory,
                5,
                cancel,
                SHELL,
            )
            self.assertEqual(cancelled["state"], "cancelled")


class PublicationTests(unittest.TestCase):
    def test_existing_draft_is_marked_ready(self):
        broker = approval.Broker.__new__(approval.Broker)
        broker.fetch_pinned = mock.Mock(return_value="jeiang/.dotfiles")
        broker.mirror_path = mock.Mock(return_value=pathlib.Path("/mirror"))
        request = {
            "branch": "codex/hermes",
            "commit": "a" * 40,
            "title": "feat: test",
            "body": "",
        }
        with mock.patch.object(
            approval,
            "run_checked",
            side_effect=["", json.dumps([{"number": 7, "isDraft": True}]), ""],
        ) as run:
            broker.publish(request)
        self.assertIn(("gh", "pr", "ready", "7", "--repo", "jeiang/.dotfiles"), [
            call.args for call in run.call_args_list
        ])


if __name__ == "__main__":
    unittest.main()
