# Custom container images

Dockerfiles for the custom images we publish to `registry.agogi.dev`. Nothing
here is deployed by ArgoCD; build and push by hand.

```
dockerfiles/
├── custom-n8n-runners/    # registry.agogi.dev/custom-n8n-runners
└── opencode-cli/          # registry.agogi.dev/opencode-cli
```

## custom-n8n-runners

Base `n8nio/runners` with the Python task runner extended (`pdfplumber`) and our
`n8n-task-runners.json`. The tag must match the n8n version.

```bash
docker build -t registry.agogi.dev/custom-n8n-runners:2.6.2 dockerfiles/custom-n8n-runners
docker push registry.agogi.dev/custom-n8n-runners:2.6.2
```

> The main n8n image (`registry.agogi.dev/custom-n8n`) has no Dockerfile here:
> the official base already ships `git`, so the image is just the upstream
> `n8nio/n8n` re-tagged.

## opencode-cli

Base `node` with the OpenCode CLI. Used as a blackbox Kubernetes Job launched by
n8n. Runs as uid `1000` to match the shared-volume owner. The image only carries
the CLI and a default config — the command lives in the Job manifest.

```bash
docker build -t registry.agogi.dev/opencode-cli:latest dockerfiles/opencode-cli
docker push registry.agogi.dev/opencode-cli:latest
```

Models come from an OpenCode Go subscription (provider `opencode-go`,
authenticated with `OPENCODE_API_KEY`).

### Job contract

The Job manifest (sent by n8n) sets the command, the working directory and the
mounts. The only required env var is the API key.

```yaml
spec:
  template:
    spec:
      workingDir: /data/shared/<repo>
      containers:
        - name: opencode
          image: registry.agogi.dev/opencode-cli:latest
          command: ["opencode"]
          args:
            - run
            - --standalone
            - --model
            - opencode-go/deepseek-v4.1-flash
            - --agent
            - coding
            - "<prompt>"
          env:
            - name: OPENCODE_API_KEY
              valueFrom:
                secretKeyRef: { name: n8n-opencode-token, key: OPENCODE_API_KEY }
          volumeMounts:
            - { name: shared, mountPath: /data/shared }
            - name: opencode
              mountPath: /home/node/.config/opencode/skills
              subPath: skills
              readOnly: true
            - name: opencode
              mountPath: /home/node/.config/opencode/agents
              subPath: agents
              readOnly: true
      volumes:
        - name: shared
          persistentVolumeClaim: { claimName: n8n-shared-pvc }
        - name: opencode
          persistentVolumeClaim: { claimName: opencode-pvc }
```

Key points:

- `opencode run --standalone` receives `OPENCODE_API_KEY` from its own process
  environment (standalone uses a private server that inherits it).
- `--agent <id>` selects the primary agent (see the agents below).

### Skills and agents

The `opencode-pvc` volume is backed by the host path `/mnt/ssd1/opencode` and is
mounted as two **sub-paths** straight into the CLI's global discovery
directories, so OpenCode finds both with no configuration:

```
/mnt/ssd1/opencode/
├── skills/    → ~/.config/opencode/skills
└── agents/    → ~/.config/opencode/agents
```

The container runs as uid `1000`, so the host directory must be readable by it:

```bash
mkdir -p /mnt/ssd1/opencode/{skills,agents}
chmod -R a+rX /mnt/ssd1/opencode
```

Agents are Markdown files (`<id>.md`): frontmatter config plus the system prompt
in the body. Starters for the code-generation flow:

`agents/coding.md`

```md
---
description: Implements the technical tasks from the spec
mode: primary
model: opencode-go/kimi-k2.7-code
steps: 60
permissions:
  - { action: edit, resource: "*", effect: allow }
  - { action: shell, resource: "*", effect: allow }
---
You are the implementation agent. Read .opencode-out/spec.md and implement the
technical tasks in order. Follow the project coding skills when relevant.
Keep changes minimal; do not commit. Write a summary to .opencode-out/coding-summary.md.
```

`agents/test.md`

```md
---
description: Turns Gherkin scenarios into tests and runs them
mode: primary
model: opencode-go/deepseek-v4-pro
steps: 50
---
You are the test agent. Read .opencode-out/spec.md (Gherkin) and the coding
changes. Write tests and run the suite. Fix only test code. Write
.opencode-out/test-summary.md with pass/fail and notes.
```

`agents/review.md`

```md
---
description: Reviews changes without editing code
mode: primary
model: opencode-go/kimi-k3
steps: 40
permissions:
  - { action: edit, resource: "*", effect: deny }
  - { action: edit, resource: ".opencode-out/review.md", effect: allow }
---
You are the review agent. Review the diff against .opencode-out/spec.md and the
coding skills. Do not modify code. Report findings by severity with file:line in
.opencode-out/review.md.
```

n8n orchestrates one phase per Job with `--agent coding` / `test` / `review`.

Store `OPENCODE_API_KEY` (and, if the workflow clones, the GitHub PAT) as
`SealedSecret`s in the `n8n` namespace and reference them from the Job.
