# ArgoCD Local Installation & Access Guide

This guide explains how to quickly install **ArgoCD** in a Kubernetes cluster, expose the UI via a **NodePort**, and retrieve the default login credentials.

---

## 1. Create the `argocd` Namespace
```bash
kubectl create namespace argocd
```

---

## 2. Install ArgoCD
Apply the official installation manifest:
```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

---

## 3. Expose the ArgoCD UI on a NodePort
Patch the argocd-server service to listen on port 30080 of your node:
```bash
kubectl -n argocd patch svc argocd-server \
  -p '{"spec": {"type": "NodePort", "ports": [{"port": 80, "targetPort": 8080, "nodePort": 30080}]}}'
```

---

## 4. Access the ArgoCD UI
Open your browser and visit:
```cpp
http://<NODE_IP>:30080
```
Replace <NODE_IP> with the IP of your Kubernetes node
(e.g. 192.168.1.30 for a local cluster).

---

## 5. Get the Default Credentials
### Username:
```nginx
admin
```
### Password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode; echo
```

✅ You now have ArgoCD installed, accessible from your local network, and ready to use.