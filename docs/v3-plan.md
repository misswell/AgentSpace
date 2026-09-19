# AgentSpace V3 — attach existing macOS accounts

## Decision

AgentSpace does not create or delete macOS users. A person creates a standard
secondary account in System Settings; AgentSpace discovers and attaches it,
installs its worker/runtime, and controls only that account's independent Aqua
desktop.

This changes the product from a user-lifecycle utility into an AI desktop
controller.

## User flow

1. Create a **standard** local user in System Settings → Users & Groups.
2. Open AgentSpace and choose **New Agent**.
3. Select an available existing macOS account and choose its display name and
   workspace.
4. AgentSpace validates the account and prepares a private runtime. If macOS has
   already created the account's home directory, it installs the worker
   LaunchAgent and starts it when the account has an Aqua session. Otherwise the
   attach is recorded as `needsLogin` and the GUI offers **Finish setup** after
   the first login; AgentSpace never creates the home directory itself.
5. Sign into that account with its existing password, return to AgentSpace and
   finish setup, then grant Accessibility plus Screen Recording to the worker
   from that account's own System Settings. The connected account does not need
   a second AgentSpace app.
6. Open and control the account's desktop from the main account.

Disconnecting reverses only AgentSpace-owned state. The macOS account and its
home directory are always retained.

## Architecture

```text
AgentSpace.app / CLI / MCP
          │
          ├── AccountDiscovery (read-only local account enumeration)
          ├── AccountAttachService (attach/detach orchestration)
          │
          ├── privileged helper
          │     ├── install/remove worker
          │     ├── prepare/remove exact runtime
          │     └── start/stop worker and inspect session
          │
          └── Unix socket JSON RPC
                    │
             agentspace-worker
                    │
        target user's WindowServer session
```

The helper exposes no shell and no account mutation API. Legacy mutation enum
values are refusal-only compatibility decoders.

## Account discovery policy

An attach candidate must:

- exist in the local passwd database;
- have uid >= 500;
- have a home below `/Users`;
- not begin with `_` and not be `root`;
- not be the current controller user;
- not be a member of `admin`;
- not already be attached.

Unknown or unprovable state fails closed.

## Runtime and worker layout

```text
/Library/Application Support/AgentSpace/
  Worker/versions/<version>/agentspace-worker
  Runtime/<account-id>/
    worker.sock
    token
    status.json
    space.json
    screenshots/
  Spaces/index.json
  Logs/
  Worktrees/
```

The worker binary and parent runtime are root-owned. A per-account runtime is
mode 0700 with inheritable ACL entries for exactly the controller account and
attached account. The worker verifies those facts before binding.

## Attach transaction

```text
validate existing standard account
→ plan workspace
→ helper prepares runtime
→ write runtime record
→ apply workspace
→ helper installs root-owned worker + user LaunchAgent
→ start worker if an Aqua session exists
→ save AgentAccount
```

Failure after runtime creation rolls back all AgentSpace-owned artifacts.

## Detach transaction

```text
stop worker
→ remove LaunchAgent
→ remove AgentSpace-created worktree
→ helper removes exact runtime
→ remove registry record
```

Detach never calls logout, `deleteUser`, `sysadminctl`, or home-directory
removal.

## Compatibility

- Keep protocol version 1 and old wire method names for compatible additions.
- Keep registry `"spaces"` and old field names; optional fields decode absent.
- Keep legacy CLI aliases and MCP tool names.
- Read the V2 registry as an upgrade source when no V3 registry exists.

## Phases

### Phase 1 — account connection

Discovery, picker, attach, worker install/start, detach, rollback, runtime ACL.

### Phase 2 — desktop control

Screenshots, click, keyboard and Desktop Viewer. Existing implementation is
retained; performance tuning remains.

### Phase 3 — agent runtime

Compose Terminal, browser, editor and agent command startup inside the attached
account.

### Phase 4 — productization

Profiles, workspace templates, MCP orchestration and menu-bar workflows.

## Acceptance

On a real Mac with a manually created standard account:

- attach succeeds without creating/changing any directory-service record;
- the worker runs from the root-owned versioned path;
- the controller and attached account can access only their runtime;
- Desktop Viewer and input operate only the target account's Aqua session;
- the main user's pointer, keyboard and applications are unaffected;
- detach removes AgentSpace state and the macOS account remains usable.
