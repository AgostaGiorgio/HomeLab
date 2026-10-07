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
            - build
            - "<prompt>"
          env:
            - name: OPENCODE_API_KEY
              valueFrom:
                secretKeyRef: { name: n8n-opencode-token, key: OPENCODE_API_KEY }
          volumeMounts:
            - { name: shared, mountPath: /data/shared }
            - { name: skills, mountPath: /opt/opencode-skills, readOnly: true }
      volumes:
        - name: shared
          persistentVolumeClaim: { claimName: n8n-shared-pvc }
        - name: skills
          persistentVolumeClaim: { claimName: opencode-skills-pvc }
```

Key points:

- `opencode run --standalone` receives `OPENCODE_API_KEY` from its own process
  environment (standalone uses a private server that inherits it).
- `--agent build` is the agent allowed to edit files (the `plan` agent denies edits).
- The prompt is an inline arg, so `n8n` shows exactly what runs.

### Skills

Skills are read from `/opt/opencode-skills` (set in the image's
`opencode.jsonc`). They are served by the `opencode-skills-pvc` volume, backed by
the host path `/mnt/ssd1/opencode-skills`. Put skill directories there:

```
/mnt/ssd1/opencode-skills/
└── my-skill/
    └── SKILL.md
```

The container runs as uid `1000`, so the host directory must be readable by it:

```bash
chmod -R a+rX /mnt/ssd1/opencode-skills
```

Store `OPENCODE_API_KEY` (and, if the workflow clones, the GitHub PAT) as
`SealedSecret`s in the `n8n` namespace and reference them from the Job.
