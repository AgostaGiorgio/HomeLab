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

> The host path must be writable by the n8n user (`node`, uid `1000`), e.g.:
> `mkdir -p /mnt/ssd1/n8n-shared && chown 1000:1000 /mnt/ssd1/n8n-shared && chmod 775 /mnt/ssd1/n8n-shared`.
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

Notes:

- Use `metadata.generateName` (not a fixed `name`) so every run creates a fresh
  Job — a `Job`'s `spec.template` is immutable and reusing the same name fails.
- Set `spec.ttlSecondsAfterFinished` so finished Jobs are cleaned up.

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
