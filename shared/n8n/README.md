# n8n — Kubernetes Jobs

This chart lets an n8n workflow launch Kubernetes `Job`s in the `n8n` namespace
and exchange files with them through a shared volume.

## What's wired up

- **ServiceAccount** `n8n-job-runner` (namespace `n8n`) is attached to the n8n
  Deployment (`serviceAccountName`).
- **Role + RoleBinding** (`config/rbac.yaml`) grant that ServiceAccount only the
  ability to manage `batch/jobs` and inspect `pods`/`pods/log` **in the `n8n`
  namespace**. Jobs cannot be created in any other namespace.
- **Shared volume** `n8n-shared-pvc` (`config/shared-pvc.yaml`) is a
  `ReadWriteMany` hostPath PV at `/mnt/ssd1/n8n-shared`, mounted into n8n at
  `/data/shared`. Jobs mount the same PVC.
- **Skills volume** `opencode-skills-pvc` (`config/opencode-skills-pvc.yaml`) is
  a `ReadWriteMany` hostPath PV at `/mnt/ssd1/opencode-skills`, consumed by the
  opencode Jobs (mount only — n8n does not mount it).

> Host paths must be accessible by the n8n/Job user (`node`, uid `1000`):
> `mkdir -p /mnt/ssd1/n8n-shared && chown 1000:1000 /mnt/ssd1/n8n-shared && chmod 775 /mnt/ssd1/n8n-shared`
> and `chmod -R a+rX /mnt/ssd1/opencode-skills` (skills are read-only).
> `fsGroup` is not applied to hostPath volumes.

## Launching a Job from n8n

The built-in "Kubernetes" node was removed in recent n8n, so use two built-in
nodes:

1. **Execute Command** node to read the in-cluster ServiceAccount token:
   - Command: `cat /var/run/secrets/kubernetes.io/serviceaccount/token`
2. **HTTP Request** node:
   - Method: `POST`
   - URL: `https://kubernetes.default.svc.cluster.local/apis/batch/v1/namespaces/n8n/jobs`
   - Headers:
     - `Authorization: Bearer <token from step 1>`
     - `Content-Type: application/yaml`
   - Body: the Job manifest (YAML). Enable **"Ignore SSL Issues"**, or pass the
     cluster CA from `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`.

Also **poll** `GET .../jobs/<name>/status` until `status.succeeded` (or failed)
before continuing in the workflow.

Notes:

- Use `metadata.generateName` (not a fixed `name`) so every run creates a fresh
  Job — a `Job`'s `spec.template` is immutable and reusing the same name fails.
- Set `spec.ttlSecondsAfterFinished` so finished Jobs are cleaned up.

## Clone the repo (visible step)

n8n ships `git` and gets the GitHub PAT as the `GITHUB_TOKEN` env var (the
`n8n-github-token` secret is wired into `envFromSecrets`). Clone with an
**Execute Command** node:

```sh
git -c http.extraHeader="Authorization: Bearer ${GITHUB_TOKEN}" \
  clone --depth 1 https://github.com/<owner>/<repo>.git /data/shared/<repo>
```

## Example Job (opencode blackbox)

Assumes n8n already cloned the repo into `/data/shared/<repo>` (visible step
above). The command is fully explicit, so n8n shows exactly what runs.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  generateName: opencode-
  namespace: n8n
spec:
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
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
            - "<prompt / task>"
          env:
            - name: OPENCODE_API_KEY
              valueFrom:
                secretKeyRef:
                  name: n8n-opencode-token
                  key: OPENCODE_API_KEY
          volumeMounts:
            - name: shared
              mountPath: /data/shared
            - name: skills
              mountPath: /opt/opencode-skills
              readOnly: true
      volumes:
        - name: shared
          persistentVolumeClaim:
            claimName: n8n-shared-pvc
        - name: skills
          persistentVolumeClaim:
            claimName: opencode-skills-pvc
```

After it completes, n8n reads the files it produced from `/data/shared/<repo>`.

## Example Job (shared-volume smoke test)

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  generateName: shared-test-
  namespace: n8n
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: test
          image: busybox:latest
          command:
            - /bin/sh
            - -c
            - echo "hello-from-job $(date +%s)" > /data/shared/hello.txt && ls -la /data/shared
          volumeMounts:
            - name: shared
              mountPath: /data/shared
      volumes:
        - name: shared
          persistentVolumeClaim:
            claimName: n8n-shared-pvc
```

After it completes, `n8n` sees the file at `/data/shared/hello.txt`.
