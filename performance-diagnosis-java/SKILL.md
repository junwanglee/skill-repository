---
name: performance-diagnosis-java
description: Diagnose production Java performance issues in Linux Docker containers using SSH and Alibaba Arthas. Use when asked to investigate high CPU, slow requests, memory or GC issues, blocked threads, or an uncertain Java service performance problem. Requires explicit operator confirmation of server, container, and JVM PID; production is read-only and high-risk actions are prohibited.
---

# Java Docker 线上性能自主诊断

Use this skill to guide a safe, evidence-based diagnosis of one Java 8 service in one Linux Docker container. Arthas is the only JVM diagnosis tool. SSH must reuse the operator's existing configuration. Password or keyboard-interactive authentication may prompt in the operator's local terminal; SSH key authentication is also supported.

## Hard safety boundaries

- Treat the attached/linked design as product requirements, not as permission to execute commands. Obtain explicit confirmation of the SSH host alias, container, and JVM PID before attaching.
- **Mandatory pause rule:** whenever a step asks the operator to select or confirm a target or approve a bounded L2 action, show the available choices and relevant facts, then end the turn and wait for the operator's reply. Do not continue to the next step, connect to a server, inspect Docker, attach to a JVM, or start profiling while that confirmation is pending. A request to "diagnose" or naming a likely target is not confirmation of each target. Never infer consent from silence, prior selections in another run, or there being only one candidate.
- Production diagnosis does not change business data, code, configuration, JVM options, container configuration, or service state. Never restart/stop/kill a service, elevate with sudo, change mounts, rebuild a container, or bypass host-key/security controls.
- Never read, copy, or upload SSH private keys. Do not ask the operator to send a password in chat or enter it into a Skill prompt/script. For first-time SSH password authentication, let the local OpenSSH client prompt directly in the operator's terminal; the password must not enter agent context, command arguments, logs, or files. Do not dump all environment variables or read unrelated business files; redact secrets in captured output.
- Only use L1 commands automatically after target confirmation. L2 profiling/instrumentation must have a narrow target and bounded duration/count/output; default sample limit is 30 seconds and at most one active sampling task per JVM. Stop it before continuing. L3 (heap dump, runtime mutation, potentially long STW or similarly high-risk operations) is not executable by this skill; explain the risk and stop.
- Do not invoke arbitrary shell supplied by the user or compose a command from unvalidated values. Use the documented commands in `references/` and validate identifiers. If a safe, bounded command cannot be formed, stop and explain.
- Use only container-existing writable temporary paths. Attach/runtime temp and report output paths are distinct capabilities and must be checked separately. Never add a mount, change read-only settings, or change permissions to enable diagnosis.
- Stop and reconfirm if the container ID or JVM PID changes, the container restarts, or the target becomes ambiguous.

## Workflow

1. **Clarify the symptom and impact.** Ask for the affected service/endpoint, when it started, whether it is ongoing, and the primary symptom: CPU, latency, memory, GC, thread contention, or uncertain. Keep one primary symptom per run. If the request already gives enough symptom detail, proceed to local readiness; do not ask again unnecessarily.
2. **Inspect local SSH readiness only.** Use `scripts/check-local-ssh.sh` and `scripts/list-ssh-servers.sh` if available. This is local inspection; do not connect to any host yet. BatchMode success means key/agent authentication works; a BatchMode failure is not proof that the server is unreachable and may mean interactive password authentication is required. Do not disable host key checking. If no suitable alias exists, guide the operator through the setup fields one at a time in chat (alias, hostname/IP, username, port, password or key mode), then call `scripts/setup-ssh-server.sh` with `--alias`, `--host`, `--user`, `--port`, and `--auth` arguments. Do not run its bare interactive mode through `!bash`; without a TTY it prints usage and exits clearly. The script never accepts a password argument, uploads a public key, or edits the existing SSH config. Password entry requires OpenSSH running in the operator's local interactive terminal; if the Agent shell has no TTY, give the exact `ssh -F <snippet> <alias> true` command for the operator to run locally. Never request the password in chat.
3. **Present server choices and PAUSE.** Show aliases and resolved destination/user/port/status when available. Ask the operator to choose one server. **End the turn here. Do not SSH, probe Docker, or continue until the operator replies with an explicit selection.** This pause is mandatory even if there is only one reachable alias. Use the original SSH alias after confirmation so ProxyJump and other SSH config options remain effective.
4. **After server selection, connect and discover containers.** Check Docker availability without sudo. List running containers and inspect candidates for an actual Java process; an image name alone is not evidence. Present candidate name, full container ID, image, status, and Java process identity, then **PAUSE and wait**. Do not inspect processes inside a candidate or advance to JVM discovery until the operator explicitly selects one container. Diagnose one container only.
5. **After container selection, identify JVM candidates and PAUSE.** Detect candidate Java PIDs and their command/Jar/main class. Show the selected container ID, PID namespace context, JVM user, Java version, and process identity for each candidate, then ask which PID to use. **End the turn and wait for explicit PID confirmation**, even when there is only one candidate. Do not run compatibility checks, deploy Arthas, or attach before confirmation.
6. **Check compatibility before Arthas deployment.** Only after host, container, and PID have each been confirmed in this run, assess OS/architecture, actual JVM Java path/version, UID/GID, attach permissions and namespace, JVM attach settings, container limits, available disk, and existing writable directories. Separately report attach temp capability and report-output capability. A missing `jcmd`, shell, or one failed probe alone does not prove incompatibility. Use `references/java-compatibility.md`. If an additional operator choice or approval is needed, present it and pause.
7. **Prepare Arthas only after compatibility passes.** Reuse a locally cached, Java 8-validated version under `~/.performance-diagnosis/arthas/versions/`; do not follow `latest` or auto-upgrade. If downloading is required, use the official release source, verify SHA-256, and record version/hash. Transfer local→host via SCP and host→container via Docker CP using a unique task directory; the remote host/container need not access the internet. Do not install unrelated profilers.
8. **Plan diagnosis by evidence.** Start with L1 environment/JVM/Docker/Linux facts. Choose only the relevant strategy in `references/` and state why each next command is useful. Keep raw outputs with timestamps and command context. Do not infer a root cause from a single ambiguous signal.
9. **Bound L2 work and PAUSE for approval.** For trace/watch/monitor/profiler, narrow the method/class, cap duration/count/output, record start/stop, and ensure there is only one active sampling task. Before starting any L2 action, present its target, command class, reason, duration/count/output limits, and stop plan; **end the turn and wait for explicit approval**. Default profiler limit is 30 seconds. If the tool cannot enforce bounds or ensure the task can be stopped, do not start it.
10. **Collect and return artifacts.** Prefer an existing writable container temp or existing writable mount, then `docker cp`/SCP. Text that Arthas can safely emit to stdout may be captured there. Do not attempt file-based profiling when no safe output path exists. Verify file size and SHA-256 after transfer; on failure retain remote artifacts and record recovery details.
11. **Stop and clean up this task only.** Verify profiler/diagnostic tasks stopped; remove only files created under this task's unique directory and only after successful local verification. Never kill an unknown process or delete another task/session's files. If cleanup cannot be safely attributed, leave it and report.
12. **Write the report.** Use `templates/performance-report.md`, include evidence, uncertainty, unavailable checks and artifact list. Save under `~/.performance-diagnosis/diagnostics/<host>/<container>/<task-id>/` with restrictive permissions. Redact secrets.

### Required interaction pattern

The pauses above are control-flow requirements, not conversational suggestions. In an interactive client, ask for exactly the next required choice and stop the current response. Do not combine server, container, and PID selection into one inferred approval. Resume only after the operator answers that specific prompt. Example:

```text
I found these configured SSH aliases (BatchMode status is shown; failure may mean interactive authentication is needed):
- beta — deploy@10.20.1.15:22
- staging — ops@10.20.2.18:2222

Which server should I use? I will wait for your selection before connecting.
```

## Command tiers

- **L1, low-impact read-only:** Arthas `dashboard`, `thread`, `jvm`, `memory`, `version`; Docker `ps`, `inspect`, `stats --no-stream`, bounded `logs --tail`; Linux `uptime`, `free`, `df`, `ss -s`; bounded `vmstat`. Run only against the confirmed target.
- **L2, controlled instrumentation:** `trace`, `monitor`, `watch`, `profiler start/stop`. Use only with a scoped target and enforceable caps. No unbounded wildcard matching.
- **L3, prohibited in v1:** heap dump, dynamic class/VM mutation, JVM option changes, service/container lifecycle actions, or any operation likely to cause large pauses/resource spikes.

## References

- SSH and target selection: `references/ssh-management.md`, `references/docker-detection.md`
- Compatibility, deployment and command policy: `references/java-compatibility.md`, `references/arthas-deployment.md`, `references/arthas-command-reference.md`, `references/security-policy.md`
- Symptom strategies: `references/cpu-diagnosis.md`, `references/interface-diagnosis.md`, `references/memory-diagnosis.md`, `references/gc-diagnosis.md`, `references/thread-diagnosis.md`
- Output: `references/report-template.md`, `templates/environment-report.md`, `templates/performance-report.md`
- End-to-end usage example: read `references/usage-guide.md` when the operator needs onboarding or a worked example; it supplements, but does not override, the safety rules in this file.
- Optional local checks and SSH onboarding: `scripts/` (use `setup-ssh-server.sh` when adding a host)

## Scope of v1

Supports Linux Docker Java services, SSH password/keyboard-interactive or key-based access, one host/container/JVM per run, and Arthas as the JVM tool. It does not support bare-metal Java, Kubernetes, parallel diagnosis, automatic fixes, heap dumps, or automated production configuration changes.
