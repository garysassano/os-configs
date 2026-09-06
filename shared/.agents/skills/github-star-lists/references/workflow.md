# Plan and recovery reference

## Permissions and API behavior

Stars and named Lists are separate operations. The REST API reads `/user/starred`; GraphQL manages `UserList` objects and their memberships. For fine-grained tokens, GitHub documents the account permission **Starring** with read access for inventory, and write access plus repository Metadata read access for star/unstar. Classic PATs use OAuth scopes instead, so their form does not contain a Starring permission; GitHub documents `public_repo` for starring public repositories. This workflow was verified with classic PATs carrying `user` and `repo`, which establishes a working configuration rather than the minimum scope for every List mutation. Test specific List operations rather than requesting unrelated administration scopes or assuming fine-grained Starring access covers them. See [REST starring endpoints](https://docs.github.com/en/rest/activity/starring), [OAuth scopes](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps), and the [GraphQL reference](https://docs.github.com/en/graphql/reference).

Operational constraints verified during implementation:

- GitHub rejects more than 32 named Lists per account. Resolve category reuse before execution.
- Fetch List metadata separately from List contents. A single large nested GraphQL query can return HTTP 502 even for fewer than a thousand starred repositories.
- REST star responses need `application/vnd.github.star+json` to include the original `starred_at` value.
- `updateUserListsForItem` replaces membership with the supplied List IDs. The CLI supports one primary List per repository on each destination account.
- Star removal clears that account's List membership. Add and verify the destination first. Re-starring cannot restore the old star date.
- The client serializes mutations with a 1.4-second minimum interval. Transient read failures receive bounded retries. Mutation errors stop the run and preserve the journal; they are not blindly retried.

## Editable plan

`draft` creates this structure from account subdirectories containing `baseline.json`:

```json
{
  "accounts": {
    "example": {
      "audit": "/absolute/path/to/audit/example",
      "categories": {
        "browser-runtime": {
          "id": "UL_existing_list_id",
          "name": "Browser Engines / DOM Runtimes",
          "description": "Embeddable browsers and executable DOM environments.",
          "isPrivate": false
        }
      }
    }
  },
  "decisions": [
    {
      "id": "repository_node_id",
      "repo": "owner/repository",
      "account": "example",
      "key": "browser-runtime",
      "reason": "Implements a DOM environment with JavaScript execution.",
      "evidence": "https://github.com/owner/repository/blob/main/README.md"
    }
  ]
}
```

Use `id: null` for a new List only when the current account has capacity. Reuse the ID of an existing List to rename or repurpose it. The set of `categories` is the final desired List set; baseline Lists omitted from it are eligible for deletion only once empty. Changing a reused List's visibility is rejected, so handle a separately authorized visibility change explicitly outside this workflow.

Every original repository must occur in at least one destination assignment. A repository can remain starred on multiple accounts by retaining an assignment for each account. The pair `(repository ID, account)` must be unique. Moving a star means changing its destination account and category; GitHub repository ownership is never transferred. Private repositories must retain their existing account placement.

## Execution artifacts

The plan is bound to its execution directory by a SHA-256 digest. Each account has a preflight snapshot, resolved category IDs, a journal of attempted and completed mutations, destination verification, a final snapshot and a verification result. JSON audit files are written with mode `0600` and newly created audit directories with mode `0700`. The CLI writes no credentials into them.

Source removal requires destination proof for the same plan, repository and List, less than 15 minutes old. `apply` refreshes proofs before each account's removal phase. The proof interval is bounded, but GitHub provides no atomic transaction spanning accounts; avoid concurrent manual edits while applying the plan. For a removal phase large enough to outlast the proof window, rerun the same command to refresh proof and resume.

To recover after a failure, inspect the last journal entries and the reported error, resolve the cause, then rerun `apply` with the same plan and execution directory. Live state is read before resuming, so a successful star addition is not repeated after a later membership failure. An interrupted List creation is adopted only when an attempted creation is journaled and an exact matching List exists. Unexpected stars, loss of retained stars, incomplete destination membership, a changed plan, account mismatches and nonempty obsolete Lists stop execution.

If rate limiting is reported, stop issuing writes, follow GitHub's retry timing, and resume the same plan. Do not replace the baseline with a partial execution snapshot or erase the journal to bypass a failed check. Rollback is a new reviewed plan built from the original snapshot and current inventory; it can restore stars and categories but cannot restore transferred star timestamps or deleted List IDs.
