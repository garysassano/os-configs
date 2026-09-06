import copy
import json
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import github_star_lists as stars


def repo(repo_id, private=False):
    return dict(
        id=repo_id, repo="owner/" + repo_id, private=private, starred_at="2020-01-01T00:00:00Z"
    )


def snapshot(account, rows, items):
    return dict(
        account=account,
        stars=rows,
        lists=[
            dict(
                id=account + "-list",
                name=account,
                description="",
                slug=account,
                isPrivate=False,
                items=items,
            )
        ],
    )


class FakeClient:
    def __init__(self, state):
        self.state = copy.deepcopy(state)
        self.account = state["account"]
        self.writes = []
        self.fail_assignment = False
        self.fail_after_create = False

    def authenticate(self):
        return {"account": self.account}

    def snapshot(self):
        return copy.deepcopy(self.state)

    def query(self, query, variables):
        data = variables["input"]
        self.writes.append(query)
        if "createUserList(" in query:
            category = dict(data, id=self.account + "-new", slug="new", items=[])
            self.state["lists"].append(category)
            if self.fail_after_create:
                self.fail_after_create = False
                raise stars.StarError("simulated lost creation response")
            return {"createUserList": {"list": category}}
        if "deleteUserList(" in query:
            self.state["lists"] = [c for c in self.state["lists"] if c["id"] != data["listId"]]
            return {"deleteUserList": {"clientMutationId": None}}
        if "addStar(" in query:
            item = repo(data["starrableId"])
            item["starred_at"] = "2026-09-06T00:00:00Z"
            self.state["stars"].append(item)
            return {"addStar": {"starrable": dict(id=item["id"], viewerHasStarred=True)}}
        if "updateUserListsForItem(" in query:
            if self.fail_assignment:
                self.fail_assignment = False
                raise stars.StarError("simulated interrupted assignment")
            for category in self.state["lists"]:
                category["items"] = [r for r in category["items"] if r != data["itemId"]]
                if category["id"] in data["listIds"]:
                    category["items"].append(data["itemId"])
            return {
                "updateUserListsForItem": dict(
                    user={"login": self.account},
                    item=dict(id=data["itemId"], viewerHasStarred=True),
                    lists=[{"id": i} for i in data["listIds"]],
                )
            }
        if "removeStar(" in query:
            self.state["stars"] = [r for r in self.state["stars"] if r["id"] != data["starrableId"]]
            for category in self.state["lists"]:
                category["items"] = [r for r in category["items"] if r != data["starrableId"]]
            return {
                "removeStar": {"starrable": dict(id=data["starrableId"], viewerHasStarred=False)}
            }
        raise AssertionError("Unexpected mutation")


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.baselines = {
            "a": snapshot("a", [repo("move"), repo("keep")], ["move", "keep"]),
            "b": snapshot("b", [repo("existing")], ["existing"]),
        }
        self.plan = dict(
            accounts={
                a: dict(
                    categories={"main": {k: v for k, v in b["lists"][0].items() if k != "items"}}
                )
                for a, b in self.baselines.items()
            },
            decisions=[
                dict(id=r, repo="owner/" + r, account=a, key="main")
                for r, a in [("keep", "a"), ("move", "b"), ("existing", "b")]
            ],
        )
        self.clients = {a: FakeClient(b) for a, b in self.baselines.items()}
        self.runner = stars.Runner(
            self.plan, self.baselines, self.tmp.name, interval=0, progress=lambda _: None
        )

    def tearDown(self):
        self.tmp.cleanup()

    def prepare(self):
        for client in self.clients.values():
            self.runner.prepare(client)

    def test_transfer_preserves_union_and_retained_dates(self):
        self.prepare()
        receipts = {a: self.runner.copy_and_categorize(c) for a, c in self.clients.items()}
        self.assertIn("move", {r["id"] for r in self.clients["a"].state["stars"]})
        self.runner.remove_sources(self.clients["a"], receipts)
        for client in self.clients.values():
            self.runner.verify(client)
        self.assertEqual(
            {r["id"] for c in self.clients.values() for r in c.state["stars"]},
            {"move", "keep", "existing"},
        )

    def test_missing_or_stale_proof_prevents_removal(self):
        self.prepare()
        with self.assertRaisesRegex(stars.StarError, "Missing destination"):
            self.runner.remove_sources(self.clients["a"], {})
        receipt = self.runner.copy_and_categorize(self.clients["b"])
        receipt["verified_at"] = time.time() - 1000
        with self.assertRaisesRegex(stars.StarError, "stale"):
            self.runner.remove_sources(self.clients["a"], {"b": receipt})
        self.assertFalse(self.clients["a"].writes)

    def test_assignment_failure_keeps_source_and_resumes_without_duplicate_star(self):
        self.prepare()
        self.clients["b"].fail_assignment = True
        with self.assertRaisesRegex(stars.StarError, "interrupted"):
            self.runner.copy_and_categorize(self.clients["b"])
        self.assertIn("move", {r["id"] for r in self.clients["a"].state["stars"]})
        self.runner.copy_and_categorize(self.clients["b"])
        self.assertEqual(sum("addStar(" in q for q in self.clients["b"].writes), 1)

    def test_repeated_apply_is_idempotent(self):
        self.test_transfer_preserves_union_and_retained_dates()
        before = sum(len(c.writes) for c in self.clients.values())
        self.prepare()
        receipts = {a: self.runner.copy_and_categorize(c) for a, c in self.clients.items()}
        for client in self.clients.values():
            self.runner.remove_sources(client, receipts)
        self.assertEqual(before, sum(len(c.writes) for c in self.clients.values()))

    def test_changed_plan_rejected_on_resume(self):
        modified = copy.deepcopy(self.plan)
        modified["decisions"][0]["reason"] = "changed"
        with self.assertRaisesRegex(stars.StarError, "Plan changed"):
            stars.Runner(modified, self.baselines, self.tmp.name)

    def test_drift_rejected_before_mutation(self):
        self.clients["a"].state["stars"].append(repo("surprise"))
        with self.assertRaisesRegex(stars.StarError, "stars changed"):
            self.runner.prepare(self.clients["a"])
        self.assertFalse(self.clients["a"].writes)

    def test_private_transfer_rejected(self):
        self.baselines["a"]["stars"][0]["private"] = True
        with self.assertRaisesRegex(stars.StarError, "Private repositories"):
            stars.validate_plan(self.plan, self.baselines)

    def test_union_loss_and_list_limit_rejected(self):
        modified = copy.deepcopy(self.plan)
        modified["decisions"].pop()
        with self.assertRaisesRegex(stars.StarError, "repository union"):
            stars.validate_plan(modified, self.baselines)
        modified = copy.deepcopy(self.plan)
        modified["accounts"]["a"]["categories"] = {str(i): {} for i in range(33)}
        with self.assertRaisesRegex(stars.StarError, "32 Lists"):
            stars.validate_plan(modified, self.baselines)

    def test_nonempty_list_is_never_deleted(self):
        self.clients["a"].state["lists"].append(dict(id="obsolete", name="old", items=["move"]))
        self.baselines["a"]["lists"].append(dict(id="obsolete", name="old", items=["move"]))
        with self.assertRaisesRegex(stars.StarError, "non-empty"):
            self.runner.retire_lists(self.clients["a"])
        self.assertFalse(self.clients["a"].writes)

    def test_credential_redaction_and_no_cross_host_request(self):
        token = "ghp_" + "a" * 36
        self.assertNotIn(token, stars.redact("error " + token))
        transport = stars.token_transport(token)
        with self.assertRaisesRegex(stars.StarError, "relative"):
            transport("//example.org")
        with self.assertRaisesRegex(stars.StarError, "relative"):
            transport("https://example.org")

    def test_gh_wrapper_account_context_and_environment(self):
        home = Path(self.tmp.name)
        wrapper = home / ".local/bin/gh"
        wrapper.parent.mkdir(parents=True)
        wrapper.touch()
        result = type(
            "Result",
            (),
            {
                "returncode": 0,
                "stdout": 'HTTP/2 200\nContent-Type: application/json\n\n{"login":"a"}',
                "stderr": "",
            },
        )()
        with (
            patch.object(stars.Path, "home", return_value=home),
            patch.object(stars.subprocess, "run", return_value=result) as run,
            patch.dict(stars.os.environ, {"GH_TOKEN": "ignore", "GITHUB_TOKEN": "ignore"}),
        ):
            request = stars.gh_transport(home)
            body, _ = request("/user")
            self.assertEqual(body["login"], "a")
            call = run.call_args
            self.assertEqual(call.args[0][0], str(wrapper))
            self.assertEqual(call.kwargs["cwd"], home)
            self.assertNotIn("GH_TOKEN", call.kwargs["env"])
            self.assertNotIn("GITHUB_TOKEN", call.kwargs["env"])
            calls_before = run.call_count
            with self.assertRaisesRegex(stars.StarError, "relative"):
                request("/https://example.org")
            self.assertEqual(run.call_count, calls_before)

    def test_account_mismatch_rejected(self):
        client = stars.GitHub("a", lambda *args, **kwargs: ({"login": "b"}, {}))
        with self.assertRaisesRegex(stars.StarError, "authenticated as b"):
            client.authenticate()

    def test_audit_files_are_private(self):
        path = Path(self.tmp.name) / "private.json"
        stars.save(path, {"safe": True})
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads(path.read_text()), {"safe": True})

    def test_wrong_list_proof_prevents_removal(self):
        self.prepare()
        receipt = self.runner.copy_and_categorize(self.clients["b"])
        receipt["destinations"]["move"] = "wrong-list"
        with self.assertRaisesRegex(stars.StarError, "not verified"):
            self.runner.remove_sources(self.clients["a"], {"b": receipt})
        self.assertFalse(self.clients["a"].writes)

    def test_empty_final_account_is_supported(self):
        plan = copy.deepcopy(self.plan)
        plan["accounts"]["a"]["categories"] = {}
        for row in plan["decisions"]:
            row["account"] = "b"
        runner = stars.Runner(
            plan, self.baselines, Path(self.tmp.name) / "empty", interval=0, progress=lambda _: None
        )
        for client in self.clients.values():
            runner.prepare(client)
        receipts = {a: runner.copy_and_categorize(c) for a, c in self.clients.items()}
        runner.remove_sources(self.clients["a"], receipts)
        runner.retire_lists(self.clients["a"])
        self.assertEqual(runner.verify(self.clients["a"])["stars"], 0)

    def test_capacity_rejected_before_partial_execution(self):
        baseline = copy.deepcopy(self.baselines)
        baseline["b"]["lists"].extend(dict(id=f"b-{i}", name=f"b-{i}", items=[]) for i in range(31))
        plan = copy.deepcopy(self.plan)
        plan["accounts"]["b"]["categories"]["main"]["id"] = None
        with self.assertRaisesRegex(stars.StarError, "exceed current capacity"):
            stars.validate_plan(plan, baseline)

    def test_lost_list_creation_response_resumes_without_duplicate(self):
        plan = copy.deepcopy(self.plan)
        plan["accounts"]["b"]["categories"]["main"].update(id=None, name="new")
        runner = stars.Runner(
            plan,
            self.baselines,
            Path(self.tmp.name) / "create",
            interval=0,
            progress=lambda _: None,
        )
        client = self.clients["b"]
        client.fail_after_create = True
        with self.assertRaisesRegex(stars.StarError, "lost creation"):
            runner.prepare(client)
        runner.prepare(client)
        self.assertEqual(sum("createUserList(" in q for q in client.writes), 1)
        self.assertEqual(runner.categories("b")["main"]["id"], "b-new")


class PaginationTests(unittest.TestCase):
    def test_all_star_list_and_membership_pages_are_read(self):
        calls = []

        def transport(path, data=None, **kwargs):
            calls.append((path, data))
            if path.startswith("/user/starred?"):
                page = int(path.split("page=100&page=")[1].split("&")[0])
                rows = []
                for i in range((page - 1) * 100, min(page * 100, 250)):
                    rows.append(
                        dict(
                            starred_at="2020",
                            repo=dict(
                                node_id=str(i),
                                full_name=f"o/r{i}",
                                description="",
                                private=False,
                                archived=False,
                            ),
                        )
                    )
                return rows, {}
            query, variables = data["query"], data["variables"]
            if "viewer { login lists" in query:
                cursor = variables["cursor"]
                categories = [
                    dict(
                        id=f"list-{i}",
                        name=f"list-{i}",
                        slug=f"list-{i}",
                        description="",
                        isPrivate=False,
                    )
                    for i in (range(20) if cursor is None else [20])
                ]
                connection = dict(
                    nodes=categories, pageInfo=dict(hasNextPage=cursor is None, endCursor="last")
                )
                return {"data": {"viewer": {"login": "a", "lists": connection}}}, {}
            total = 151 if variables["id"] == "list-0" else 1
            start = 0 if variables["after"] is None else 100
            connection = dict(
                totalCount=total,
                nodes=[{"id": str(i)} for i in range(start, min(start + 100, total))],
                pageInfo=dict(hasNextPage=start + 100 < total, endCursor="more"),
            )
            return {"data": {"node": {"items": connection}}}, {}

        result = stars.GitHub("a", transport).snapshot()
        self.assertEqual(len(result["stars"]), 250)
        self.assertEqual(len(result["lists"]), 21)
        self.assertEqual(len(result["lists"][0]["items"]), 151)
        self.assertEqual(len([p for p, _ in calls if p.startswith("/user/starred?")]), 3)


if __name__ == "__main__":
    unittest.main()
