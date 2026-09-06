#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Inventory and reorganize GitHub stars and named Lists with a resumable audit."""

from __future__ import annotations

import argparse
import base64
import getpass
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from pathlib import Path


class StarError(Exception):
    """Actionable failure without credential contents."""


def require(condition, message):
    if not condition:
        raise StarError(message)


def emit(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


def load(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    tmp = path.with_suffix(path.suffix + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    os.replace(tmp, path)


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def redact(value):
    return re.sub(r"(?:gh[pousr]_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+)", "[REDACTED]", str(value))


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def token_transport(token):
    """Keep an explicitly supplied PAT in a closure; never put it in argv or env."""
    opener = urllib.request.build_opener(NoRedirect())

    def request(path, data=None, method=None, accept="application/vnd.github+json"):
        require(
            path.startswith("/") and not path.startswith("//") and "://" not in path,
            "API path must be relative",
        )
        req = urllib.request.Request(
            "https://api.github.com" + path,
            data=None if data is None else json.dumps(data).encode(),
            method=method or ("POST" if data is not None else "GET"),
            headers={
                "Authorization": "Bearer " + token,
                "Accept": accept,
                "Content-Type": "application/json",
                "User-Agent": "github-star-lists",
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        try:
            with opener.open(req, timeout=45) as response:
                raw = response.read()
                headers = {k.lower(): v for k, v in response.headers.items()}
                body = (
                    json.loads(raw)
                    if raw and "json" in headers.get("content-type", "")
                    else raw.decode()
                )
                return body, headers
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace").replace(token, "[REDACTED]")
            raise StarError(f"GitHub HTTP {exc.code}: {redact(detail[:1200])}") from None

    return request


def gh_transport(repo):
    """Always invoke the account wrapper in the supplied target repository."""
    repo = Path(repo).expanduser().resolve()
    require(repo.is_dir(), f"Missing repository directory: {repo}")
    check = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "--show-toplevel"], capture_output=True, text=True
    )
    require(check.returncode == 0, f"Not inside a Git repository: {repo}")
    wrapper = Path.home() / ".local/bin/gh"
    executable = str(wrapper) if wrapper.exists() else shutil.which("gh")
    require(executable, "GitHub CLI is missing; use the machine tool manager")

    def request(path, data=None, method=None, accept="application/vnd.github+json"):
        require(
            path.startswith("/") and not path.startswith("//") and "://" not in path,
            "API path must be relative",
        )
        command = [
            executable,
            "api",
            path.lstrip("/"),
            "--include",
            "--method",
            method or ("POST" if data is not None else "GET"),
            "-H",
            "Accept: " + accept,
            "-H",
            "X-GitHub-Api-Version: 2022-11-28",
        ]
        if data is not None:
            command += ["--input", "-"]
        environment = {k: v for k, v in os.environ.items() if k not in ("GH_TOKEN", "GITHUB_TOKEN")}
        result = subprocess.run(
            command,
            cwd=repo,
            env=environment,
            input=json.dumps(data) if data is not None else None,
            capture_output=True,
            text=True,
            timeout=60,
        )
        require(result.returncode == 0, "GitHub CLI failed: " + redact(result.stderr[:1200]))
        header, separator, body = result.stdout.partition("\n\n")
        require(separator, "GitHub CLI returned no HTTP headers")
        headers = {
            k.lower(): v.strip()
            for line in header.splitlines()
            if ": " in line
            for k, v in [line.split(": ", 1)]
        }
        return (
            json.loads(body) if body.strip() and "json" in headers.get("content-type", "") else body
        ), headers

    return request


class GitHub:
    def __init__(self, account, transport):
        self.account = account
        self.transport = transport

    def authenticate(self):
        user, headers = self.transport("/user")
        require(
            user["login"].casefold() == self.account.casefold(),
            f"Expected {self.account}, authenticated as {user['login']}",
        )
        return {
            "account": user["login"],
            "scopes": headers.get("x-oauth-scopes"),
            "expires": headers.get("github-authentication-token-expiration"),
        }

    def query(self, query, variables=None):
        data, _ = self.transport("/graphql", {"query": query, "variables": variables or {}})
        require(not data.get("errors"), "GraphQL: " + redact(json.dumps(data.get("errors"))))
        return data["data"]

    def read(self, operation):
        for attempt in range(3):
            try:
                return operation()
            except Exception as exc:
                transient = any(
                    s in str(exc).lower()
                    for s in ("http 500", "http 502", "http 503", "http 504", "timed out")
                )
                if not transient or attempt == 2:
                    raise
                time.sleep(2**attempt)
        raise StarError("Read retry exhausted")

    def snapshot(self):
        stars = []
        page = 1
        while True:
            rows, _ = self.read(
                lambda page=page: self.transport(
                    f"/user/starred?per_page=100&page={page}&sort=created&direction=asc",
                    accept="application/vnd.github.star+json",
                )
            )
            for row in rows:
                r = row["repo"]
                stars.append(
                    dict(
                        id=r["node_id"],
                        repo=r["full_name"],
                        starred_at=row["starred_at"],
                        description=r["description"],
                        private=r["private"],
                        archived=r["archived"],
                        topics=r.get("topics", []),
                        homepage=r.get("homepage"),
                    )
                )
            if len(rows) < 100:
                break
            page += 1
        require(
            len({r["id"] for r in stars}) == len(stars),
            "Duplicate star during pagination; take a fresh inventory",
        )
        lists, cursor = [], None
        while True:
            viewer = self.read(
                lambda cursor=cursor: self.query(
                    """query($cursor:String) { viewer { login lists(first:20,after:$cursor) {
                nodes { id name slug description isPrivate } pageInfo { hasNextPage endCursor }
            } } }""",
                    {"cursor": cursor},
                )
            )["viewer"]
            require(viewer["login"] == self.account, "Account changed during inventory")
            connection = viewer["lists"]
            lists.extend(connection["nodes"])
            if not connection["pageInfo"]["hasNextPage"]:
                break
            cursor = connection["pageInfo"]["endCursor"]

        def members(item):
            found, after = [], None
            while True:
                connection = self.read(
                    lambda after=after: self.query(
                        """query($id:ID!,$after:String) {
                    node(id:$id) { ... on UserList { items(first:100,after:$after) {
                        totalCount nodes { ... on Repository { id } } pageInfo { hasNextPage endCursor }
                    } } }
                }""",
                        {"id": item["id"], "after": after},
                    )
                )["node"]["items"]
                require(
                    all("id" in n for n in connection["nodes"]),
                    "Unexpected non-repository List item",
                )
                found.extend(n["id"] for n in connection["nodes"])
                if not connection["pageInfo"]["hasNextPage"]:
                    break
                after = connection["pageInfo"]["endCursor"]
            require(
                len(found) == connection["totalCount"] == len(set(found)),
                "List changed during pagination",
            )
            return dict(item, items=found)

        with ThreadPoolExecutor(max_workers=3) as pool:
            lists = list(pool.map(members, lists))
        return dict(
            account=self.account,
            captured_at=datetime.now(UTC).isoformat(),
            stars=stars,
            lists=lists,
        )

    def readme(self, repo):
        result, _ = self.read(lambda: self.transport(f"/repos/{repo}/readme"))
        require(result.get("encoding") == "base64", f"Unexpected README encoding for {repo}")
        return base64.b64decode(result["content"]).decode(errors="replace"), result["html_url"]


def memberships(snapshot):
    result = {}
    for item in snapshot["lists"]:
        for repo_id in item["items"]:
            result.setdefault(repo_id, set()).add(item["id"])
    return result


def account_rows(plan, account):
    return [r for r in plan["decisions"] if r["account"] == account]


def validate_plan(plan, baselines):
    require(set(plan["accounts"]) == set(baselines), "Plan accounts and inventories differ")
    original_ids = {r["id"] for b in baselines.values() for r in b["stars"]}
    require(
        {r["id"] for r in plan["decisions"]} == original_ids,
        "Plan must preserve the complete repository union",
    )
    require(
        len({(r["id"], r["account"]) for r in plan["decisions"]}) == len(plan["decisions"]),
        "Duplicate destination assignment",
    )
    for account, settings in plan["accounts"].items():
        cats = settings["categories"]
        require(len(cats) <= 32, f"{account}: GitHub permits at most 32 Lists")
        require(
            len({c["name"].casefold() for c in cats.values()}) == len(cats),
            f"{account}: duplicate List names",
        )
        ids = [c["id"] for c in cats.values() if c.get("id")]
        require(len(ids) == len(set(ids)), f"{account}: reused List ID in multiple categories")
        existing = {c["id"]: c for c in baselines[account]["lists"]}
        require(set(ids) <= set(existing), f"{account}: List ID does not belong to account")
        require(
            len(existing) + sum(not c.get("id") for c in cats.values()) <= 32,
            f"{account}: new Lists exceed current capacity; repurpose existing List IDs",
        )
        for c in cats.values():
            require(
                c.get("name") and isinstance(c.get("isPrivate"), bool),
                "List name and visibility required",
            )
            if c.get("id"):
                require(
                    c["isPrivate"] == existing[c["id"]]["isPrivate"],
                    "Visibility changes require a separate reviewed action",
                )
    for r in plan["decisions"]:
        require(r["account"] in plan["accounts"], "Unknown destination account")
        require(
            r["key"] in plan["accounts"][r["account"]]["categories"],
            f"Missing category: {r['repo']}",
        )
        originals = [b for b in baselines.values() if any(s["id"] == r["id"] for s in b["stars"])]
        private = any(s["private"] for b in originals for s in b["stars"] if s["id"] == r["id"])
        require(
            not private or any(b["account"] == r["account"] for b in originals),
            "Private repositories must stay on their existing accounts",
        )
    return True


class Runner:
    def __init__(self, plan, baselines, state, interval=1.4, progress=emit):
        validate_plan(plan, baselines)
        self.plan, self.baselines = plan, baselines
        self.state = Path(state)
        self.state.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.hash = digest(plan)
        self.interval, self.progress = interval, progress
        self.last_write = 0.0
        marker = self.state / "plan-hash.json"
        if marker.exists():
            require(
                load(marker) == self.hash,
                "Plan changed after execution started; inspect the audit before continuing",
            )
        else:
            save(marker, self.hash)

    def path(self, account, name):
        require(account in self.plan["accounts"], "Unknown account")
        return self.state / account / name

    def categories(self, account):
        path = self.path(account, "categories.json")
        return load(path) if path.exists() else self.plan["accounts"][account]["categories"]

    def mutate(self, client, kind, query, variables):
        time.sleep(max(0, self.interval - (time.monotonic() - self.last_write)))
        self.last_write = time.monotonic()
        path = self.path(client.account, "journal.jsonl")
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)

        def journal(status, **extra):
            fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
            with os.fdopen(fd, "a") as stream:
                stream.write(
                    json.dumps(
                        dict(
                            at=datetime.now(UTC).isoformat(),
                            status=status,
                            kind=kind,
                            variables=variables,
                            **extra,
                        ),
                        ensure_ascii=False,
                    )
                    + "\n"
                )
                stream.flush()
                os.fsync(stream.fileno())

        journal("started")
        # A mutation failure is intentionally not blindly retried. Resume reads live state.
        result = client.query(query, variables)
        journal("completed", result=result)
        return result

    def preflight(self, client):
        client.authenticate()
        account = client.account
        live = client.snapshot()
        baseline = self.baselines[account]
        marker = self.path(account, "preflight.json")
        if not marker.exists():
            require(
                {r["id"]: r["starred_at"] for r in live["stars"]}
                == {r["id"]: r["starred_at"] for r in baseline["stars"]},
                f"{account}: stars changed after inventory",
            )
            require(
                memberships(live) == memberships(baseline),
                f"{account}: List memberships changed after inventory",
            )

            def meta(s):
                return {c["id"]: (c["name"], c["description"], c["isPrivate"]) for c in s["lists"]}

            require(
                meta(live) == meta(baseline), f"{account}: List metadata changed after inventory"
            )
            save(marker, live)
        old = {r["id"] for r in baseline["stars"]}
        desired = {r["id"] for r in account_rows(self.plan, account)}
        actual = {r["id"] for r in live["stars"]}
        require(
            actual <= old | desired,
            f"{account}: unexpected stars appeared; inspect before continuing",
        )
        require(old & desired <= actual, f"{account}: a retained star disappeared")
        return live

    def prepare(self, client):
        live = self.preflight(client)
        account = client.account
        existing = {c["id"]: c for c in live["lists"]}
        cats = self.categories(account)
        for key, c in cats.items():
            if not c.get("id"):
                # Adopt only an exact List from an interrupted, journaled creation.
                candidates = [
                    x
                    for x in existing.values()
                    if all(x.get(k) == c.get(k) for k in ("name", "description", "isPrivate"))
                ]
                journal = self.path(account, "journal.jsonl")
                attempted = journal.exists() and any(
                    x.get("kind") == "create_list"
                    and x["variables"].get("input", {}).get("name") == c["name"]
                    for x in map(json.loads, journal.read_text().splitlines())
                )
                if candidates and attempted:
                    require(len(candidates) == 1, "Ambiguous interrupted List creation")
                    c["id"] = candidates[0]["id"]
                else:
                    require(
                        len(existing) < 32,
                        f"{account}: at the 32-List limit; repurpose an existing List ID in the plan",
                    )
                    result = self.mutate(
                        client,
                        "create_list",
                        """mutation($input:CreateUserListInput!) {
                        createUserList(input:$input) { list { id name slug description isPrivate } }
                    }""",
                        {"input": {k: c[k] for k in ("name", "description", "isPrivate")}},
                    )["createUserList"]["list"]
                    c["id"] = result["id"]
                    existing[c["id"]] = dict(result, items=[])
            require(c["id"] in existing, f"{account}: planned List disappeared")
            before = existing[c["id"]]
            if any(before.get(k) != c.get(k) for k in ("name", "description", "isPrivate")):
                result = self.mutate(
                    client,
                    "update_list",
                    """mutation($input:UpdateUserListInput!) {
                    updateUserList(input:$input) { list { id name slug description isPrivate } }
                }""",
                    {
                        "input": dict(
                            listId=c["id"],
                            **{k: c[k] for k in ("name", "description", "isPrivate")},
                        )
                    },
                )["updateUserList"]["list"]
                require(
                    all(result[k] == c[k] for k in ("id", "name", "description", "isPrivate")),
                    "List metadata mutation did not match",
                )
            cats[key] = c
            save(self.path(account, "categories.json"), cats)
        self.progress({"account": account, "lists_prepared": len(cats)})

    def copy_and_categorize(self, client):
        live = self.preflight(client)
        account = client.account
        cats = self.categories(account)
        require(
            all(c.get("id") for c in cats.values()), "Prepare Lists before assigning repositories"
        )
        current = memberships(live)
        starred = {r["id"] for r in live["stars"]}
        rows = sorted(
            account_rows(self.plan, account),
            key=lambda r: (not r.get("priority", False), r["id"] in starred, r["repo"].casefold()),
        )
        changed, added = 0, 0
        for row in rows:
            repo_id, target = row["id"], cats[row["key"]]["id"]
            if repo_id not in starred:
                result = self.mutate(
                    client,
                    "add_star",
                    """mutation($input:AddStarInput!) {
                    addStar(input:$input) { starrable { id viewerHasStarred } }
                }""",
                    {"input": {"starrableId": repo_id}},
                )["addStar"]["starrable"]
                require(
                    result["id"] == repo_id and result["viewerHasStarred"],
                    "Destination star was not added",
                )
                starred.add(repo_id)
                added += 1
            if current.get(repo_id, set()) != {target}:
                result = self.mutate(
                    client,
                    "assign_list",
                    """mutation($input:UpdateUserListsForItemInput!) {
                    updateUserListsForItem(input:$input) { item { ... on Repository { id viewerHasStarred } }
                        lists { id } user { login } }
                }""",
                    {"input": {"itemId": repo_id, "listIds": [target]}},
                )["updateUserListsForItem"]
                require(
                    result["user"]["login"] == account
                    and result["item"]["id"] == repo_id
                    and result["item"]["viewerHasStarred"],
                    "Assignment returned wrong account or repository",
                )
                require(
                    {c["id"] for c in result["lists"]} == {target},
                    "Destination List assignment failed",
                )
                current[repo_id] = {target}
                changed += 1
                if changed == 1 or changed % 20 == 0:
                    self.progress(
                        {
                            "account": account,
                            "categorized": changed,
                            "stars_added": added,
                            "latest": row["repo"],
                        }
                    )
        receipt = self.receipt(client)
        self.progress(
            {
                "account": account,
                "copy_verified": len(receipt["destinations"]),
                "categorized": changed,
                "stars_added": added,
            }
        )
        return receipt

    def receipt(self, client):
        live = client.snapshot()
        account = client.account
        cats, observed = self.categories(account), memberships(live)
        stars = {r["id"] for r in live["stars"]}
        destinations = {r["id"]: cats[r["key"]]["id"] for r in account_rows(self.plan, account)}
        require(set(destinations) <= stars, f"{account}: destination stars are missing")
        require(
            all(observed.get(repo_id) == {target} for repo_id, target in destinations.items()),
            f"{account}: destination List verification failed",
        )
        receipt = dict(
            account=account, plan_hash=self.hash, verified_at=time.time(), destinations=destinations
        )
        save(self.path(account, "copy-snapshot.json"), live)
        save(self.path(account, "copy-verified.json"), receipt)
        return receipt

    def remove_sources(self, client, receipts):
        account = client.account
        live = self.preflight(client)
        desired = {r["id"] for r in account_rows(self.plan, account)}
        outgoing = {r["id"] for r in self.baselines[account]["stars"]} - desired
        actual = {r["id"] for r in live["stars"]}
        for i, repo_id in enumerate(sorted(outgoing & actual), 1):
            destinations = [r for r in self.plan["decisions"] if r["id"] == repo_id]
            require(destinations, "Refusing to remove the last planned star")
            for row in destinations:
                dest = row["account"]
                receipt = receipts.get(dest, {})
                require(
                    receipt.get("plan_hash") == self.hash and receipt.get("account") == dest,
                    "Missing destination verification for this plan",
                )
                require(
                    0 <= time.time() - receipt.get("verified_at", 0) < 900,
                    "Destination proof is stale; refresh receipts before removing source stars",
                )
                target = self.categories(dest)[row["key"]]["id"]
                require(
                    receipt.get("destinations", {}).get(repo_id) == target,
                    "Destination star and List are not verified",
                )
            result = self.mutate(
                client,
                "remove_star",
                """mutation($input:RemoveStarInput!) {
                removeStar(input:$input) { starrable { id viewerHasStarred } }
            }""",
                {"input": {"starrableId": repo_id}},
            )["removeStar"]["starrable"]
            require(
                result["id"] == repo_id and not result["viewerHasStarred"],
                "Source star was not removed",
            )
            if i == 1 or i % 20 == 0:
                self.progress(
                    {"account": account, "source_stars_removed": i, "total": len(outgoing & actual)}
                )

    def retire_lists(self, client):
        live = client.snapshot()
        used = {c["id"] for c in self.categories(client.account).values()}
        baseline_ids = {c["id"] for c in self.baselines[client.account]["lists"]}
        for c in live["lists"]:
            if c["id"] not in used:
                require(c["id"] in baseline_ids, "Unexpected List appeared; refusing to delete it")
                require(not c["items"], f"Refusing to delete non-empty List: {c['name']}")
                self.mutate(
                    client,
                    "delete_empty_list",
                    """mutation($input:DeleteUserListInput!) {
                    deleteUserList(input:$input) { clientMutationId }
                }""",
                    {"input": {"listId": c["id"]}},
                )

    def verify(self, client):
        live = client.snapshot()
        account = client.account
        cats = self.categories(account)
        desired = {r["id"]: cats[r["key"]]["id"] for r in account_rows(self.plan, account)}
        stars = {r["id"]: r for r in live["stars"]}
        require(set(stars) == set(desired), f"{account}: final star set differs from plan")
        require(
            memberships(live) == {r: {c} for r, c in desired.items()},
            f"{account}: final List memberships differ",
        )
        lists = {c["id"]: c for c in live["lists"]}
        require(
            set(lists) == {c["id"] for c in cats.values()}, f"{account}: final List set differs"
        )
        for c in cats.values():
            require(
                all(lists[c["id"]][k] == c[k] for k in ("name", "description", "isPrivate")),
                f"{account}: final List metadata differs",
            )
        retained = [r for r in self.baselines[account]["stars"] if r["id"] in desired]
        require(
            all(stars[r["id"]]["starred_at"] == r["starred_at"] for r in retained),
            f"{account}: a retained star timestamp changed",
        )
        result = dict(
            account=account,
            verified_at=datetime.now(UTC).isoformat(),
            plan_hash=self.hash,
            stars=len(stars),
            lists=len(lists),
            all_memberships_match=True,
            retained_star_dates_preserved=True,
        )
        save(self.path(account, "final-snapshot.json"), live)
        save(self.path(account, "verified.json"), result)
        self.progress(result)
        return result


def clients_from_args(args):
    clients = {}
    for value in args.repo:
        account, sep, repo = value.partition("=")
        require(sep and account not in clients, "--repo needs a unique ACCOUNT=/path/to/repository")
        clients[account] = GitHub(account, gh_transport(repo))
    for account in args.prompt_token:
        require(account not in clients, f"Duplicate authentication choice: {account}")
        require(
            sys.stdin.isatty(),
            "PAT input needs a terminal; tokens are not accepted as arguments or environment variables",
        )
        token = getpass.getpass(f"Temporary GitHub token for {account}: ")
        require(bool(token), "Empty token")
        clients[account] = GitHub(account, token_transport(token))
        token = None
    for client in clients.values():
        emit(client.authenticate())
    return clients


def baselines_for(plan):
    return {a: load(Path(s["audit"]) / "baseline.json") for a, s in plan["accounts"].items()}


def draft_plan(root):
    baselines = [load(path) for path in sorted(Path(root).glob("*/baseline.json"))]
    require(baselines, "No account inventories found")
    accounts, rows = {}, []
    for b in baselines:
        account = b["account"]
        cats = {
            f"list-{i + 1}": {k: c[k] for k in ("id", "name", "description", "isPrivate")}
            for i, c in enumerate(b["lists"])
        }
        list_keys = {c["id"]: key for key, c in cats.items()}
        observed = memberships(b)
        if any(not observed.get(r["id"]) for r in b["stars"]):
            cats["uncategorized"] = dict(
                id=None,
                name="Uncategorized",
                description="Repositories awaiting review.",
                isPrivate=False,
            )
        accounts[account] = dict(audit=str((Path(root) / account).resolve()), categories=cats)
        for r in b["stars"]:
            keys = sorted(list_keys[c] for c in observed.get(r["id"], set()))
            rows.append(
                dict(
                    id=r["id"],
                    repo=r["repo"],
                    account=account,
                    key=keys[0] if keys else "uncategorized",
                    original_lists=keys,
                    description=r["description"],
                    reason="",
                    evidence="https://github.com/" + r["repo"],
                )
            )
    return dict(accounts=accounts, decisions=rows)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo",
        action="append",
        default=[],
        metavar="ACCOUNT=PATH",
        help="Authenticate through gh in this mapped repository",
    )
    parser.add_argument(
        "--prompt-token",
        action="append",
        default=[],
        metavar="ACCOUNT",
        help="Read an explicitly authorized temporary PAT without echo",
    )
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("auth", help="Check token/account identity and reported scopes")
    inventory = sub.add_parser(
        "inventory", help="Save all stars and paginated Lists without mutation"
    )
    inventory.add_argument("--out", type=Path, required=True)
    draft = sub.add_parser(
        "draft", help="Generate an editable plan; does not classify repositories"
    )
    draft.add_argument("--inventory", type=Path, required=True)
    draft.add_argument("--out", type=Path, required=True)
    evidence = sub.add_parser("evidence", help="Download current README evidence for an inventory")
    evidence.add_argument("--inventory", type=Path, required=True)
    for command in ("check", "apply", "verify"):
        p = sub.add_parser(command)
        p.add_argument("--plan", type=Path, required=True)
        if command != "check":
            p.add_argument("--state", type=Path, required=True)
    args = parser.parse_args(argv)
    if args.command == "draft":
        require(not args.out.exists(), "Refusing to overwrite an existing plan")
        plan = draft_plan(args.inventory)
        save(args.out, plan)
        emit(
            {
                "draft": str(args.out),
                "assignments": len(plan["decisions"]),
                "needs_semantic_review": True,
            }
        )
        return
    if args.command in ("check", "apply", "verify"):
        plan = load(args.plan)
        baselines = baselines_for(plan)
        validate_plan(plan, baselines)
        require(
            all(r.get("reason") and r.get("evidence") for r in plan["decisions"]),
            "Every repository needs a reviewed reason and evidence source",
        )
        if args.command == "check":
            emit(
                {
                    "valid": True,
                    "assignments": len(plan["decisions"]),
                    "unique_repositories": len({r["id"] for r in plan["decisions"]}),
                }
            )
            return
    clients = clients_from_args(args)
    require(clients, "Supply --repo ACCOUNT=PATH or --prompt-token ACCOUNT before the command")
    if args.command == "auth":
        return
    if args.command == "inventory":
        for account, client in clients.items():
            path = args.out / account / "baseline.json"
            require(not path.exists(), f"Refusing to overwrite inventory: {path}")
            snapshot = client.snapshot()
            save(path, snapshot)
            emit(
                {
                    "account": account,
                    "stars": len(snapshot["stars"]),
                    "lists": len(snapshot["lists"]),
                    "inventory": str(path),
                }
            )
        return
    if args.command == "evidence":
        for account, client in clients.items():
            baseline = load(args.inventory / account / "baseline.json")
            output = args.inventory / account / "readmes"
            output.mkdir(parents=True, exist_ok=True, mode=0o700)
            index = []
            for row in baseline["stars"]:
                try:
                    body, url = client.readme(row["repo"])
                    path = output / (row["repo"].replace("/", "__") + ".md")
                    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                    with os.fdopen(fd, "w") as stream:
                        stream.write(body)
                    index.append(dict(repo=row["repo"], source=url, path=str(path)))
                except StarError as exc:
                    if "HTTP 404" not in str(exc):
                        raise
                    index.append(dict(repo=row["repo"], error="No README; inspect source tree"))
                if len(index) % 50 == 0:
                    emit({"account": account, "readmes": len(index)})
            save(args.inventory / account / "readme-index.json", index)
        return
    require(set(clients) == set(plan["accounts"]), "Authenticate every account in the plan")
    runner = Runner(plan, baselines, args.state)
    if args.command == "apply":
        # Preflight every account before the first mutation.
        for client in clients.values():
            runner.preflight(client)
        for client in clients.values():
            runner.prepare(client)
        for client in clients.values():
            runner.copy_and_categorize(client)
        for client in clients.values():
            receipts = {a: runner.receipt(c) for a, c in clients.items()}
            runner.remove_sources(client, receipts)
        for client in clients.values():
            runner.retire_lists(client)
    results = [runner.verify(client) for client in clients.values()]
    save(
        args.state / "verified.json",
        dict(
            plan_hash=runner.hash,
            accounts=results,
            unique_repositories=len({r["id"] for r in plan["decisions"]}),
        ),
    )


if __name__ == "__main__":
    os.umask(0o077)
    try:
        main()
    except (StarError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print(redact(exc), file=sys.stderr)
        sys.exit(1)
