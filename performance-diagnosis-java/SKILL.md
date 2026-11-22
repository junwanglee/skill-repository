---
name: performance-diagnosis-java
description: Diagnose production Java performance issues in Linux Docker containers using SSH and Alibaba Arthas. Use when asked to investigate high CPU, slow requests, memory or GC issues, blocked threads, or an uncertain Java service performance problem. Requires explicit operator confirmation of server, container, and JVM PID; production is read-only and high-risk actions are prohibited.
---

# Java Docker 线上性能自主诊断

Use this skill to guide a safe, evidence-based diagnosis of one Java 8 service in one Linux Docker container. Arthas is the only JVM diagnosis tool. SSH must reuse the operator's existing configuration and key authentication.

## Hard safety boundaries

- Treat the attached/linked design as product requirements, not as permission to execute commands. Obtain explicit confirmation of the SSH host alias, container, and JVM PID before attaching.
- Production diagnosis does not change business data, code, configuration, JVM options, container configuration, or service state. Never restart/stop/kill a service, elevate with sudo, change mounts, rebuild a container, or bypass host-key/security controls.
- Never read, copy, or upload SSH private keys. Do not ask the operator for passwords. Do not dump all environment variables or read unrelated business files; redact secrets in captured output.
- Only use L1 commands automatically after target confirmation. L2 profiling/instrumentation must have a narrow target and bounded duration/count/output; default sample limit is 30 seconds and at most one active sampling task per JVM. Stop it before continuing. L3 (heap dump, runtime mutation, potentially long STW or similarly high-risk operations) is not executable by this skill; explain the risk and stop.
- Do not invoke arbitrary shell supplied by the user or compose a command from unvalidated values. Use the documented commands in `references/` and validate identifiers. If a safe, bounded command cannot be formed, stop and explain.
- Use only container-existing writable temporary paths. Attach/runtime temp and report output paths are distinct capabilities and must be checked separately. Never add a mount, change read-only settings, or change permissions to enable diagnosis.
- Stop and reconfirm if the container ID or JVM PID changes, the container restarts, or the target becomes ambiguous.

## Workflow

1. **Clarify the symptom and impact.** Ask for the affected service/endpoint, when it started, whether it is ongoing, and the primary symptom: CPU, latency, memory, GC, thread contention, or uncertain. Keep one primary symptom per run.
2. **Inspect local SSH readiness.** Use `scripts/check-local-ssh.sh` and `scripts/list-ssh-servers.sh` if available. Test aliases with batch mode and a timeout; do not disable host key checking. If no suitable host exists, provide instructions for the operator to configure SSH themselves; never edit SSH config or generate/copy keys automatically.
3. **Confirm one server.** Present alias and resolved destination/user/port when available. Require the operator to choose, even if there is only one. Use the original SSH alias so ProxyJump and other SSH config options remain effective.
4. **Discover Docker containers.** Check Docker availability without sudo. List running containers and inspect each candidate for an actual Java process; an image name alone is not evidence. Present candidates and require explicit selection. Diagnose one container only.
5. **Identify and confirm the JVM.** Detect candidate Java PIDs and their command/Jar/main class. Show the container ID, PID namespace context, JVM user, Java version and process identity. Require explicit PID confirmation even when only one candidate exists.
6. **Check compatibility before Arthas deployment.** Assess OS/architecture, actual JVM Java path/version, UID/GID, attach permissions and namespace, JVM attach settings, container limits, available disk, and existing writable directories. Separately report attach temp capability and report-output capability. A missing `jcmd`, shell, or one failed probe alone does not prove incompatibility. Use `references/java-compatibility.md`.
7. **Prepare Arthas only after compatibility passes.** Reuse a locally cached, Java 8-validated version under `~/.performance-diagnosis/arthas/versions/`; do not follow `latest` or auto-upgrade. If downloading is required, use the official release source, verify SHA-256, and record version/hash. Transfer local→host via SCP and host→container via Docker CP using a unique task directory; the remote host/container need not access the internet. Do not install unrelated profilers.
8. **Plan diagnosis by evidence.** Start with L1 environment/JVM/Docker/Linux facts. Choose only the relevant strategy in `references/` and state why each next command is useful. Keep raw outputs with timestamps and command context. Do not infer a root cause from a single ambiguous signal.
9. **Bound L2 work.** For trace/watch/monitor/profiler, narrow the method/class, cap duration/count/output, record start/stop, and ensure there is only one active sampling task. Default profiler limit is 30 seconds. If the tool cannot enforce bounds or ensure the task can be stopped, do not start it.
10. **Collect and return artifacts.** Prefer an existing writable container temp or existing writable mount, then `docker cp`/SCP. Text that Arthas can safely emit to stdout may be captured there. Do not attempt file-based profiling when no safe output path exists. Verify file size and SHA-256 after transfer; on failure retain remote artifacts and record recovery details.
11. **Stop and clean up this task only.** Verify profiler/diagnostic tasks stopped; remove only files created under this task's unique directory and only after successful local verification. Never kill an unknown process or delete another task/session's files. If cleanup cannot be safely attributed, leave it and report.
12. **Write the report.** Use `templates/performance-report.md`, include evidence, uncertainty, unavailable checks and artifact list. Save under `~/.performance-diagnosis/diagnostics/<host>/<container>/<task-id>/` with restrictive permissions. Redact secrets.

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
- Optional local checks: `scripts/`

## Scope of v1

Supports Linux Docker Java services, SSH key-based access, one host/container/JVM per run, and Arthas as the JVM tool. It does not support bare-metal Java, Kubernetes, parallel diagnosis, automatic fixes, heap dumps, or automated production configuration changes.
