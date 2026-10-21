# Cheapkart Kubernetes manifests

These manifests deploy the frontend and backend to the existing `cheapkart-eks` cluster. They do not create the EKS cluster or build/push Docker images.

## Traffic design

- `cheapkart-frontend` is the only public application Service (`LoadBalancer`, HTTP/80).
- `cheapkart-backend` is a private `ClusterIP` Service on port 5000.
- Frontend Nginx serves the React app and proxies `/api/*` to `http://cheapkart-backend:5000` inside the `cheapkart` namespace. The frontend build uses a same-origin relative API URL, so it does not need a public backend hostname.
- The backend has one replica because each backend process subscribes to Solace events and sends emails. Running multiple replicas with the current subscription can duplicate notifications.

## Values to update before applying

1. Set the image names and tags in `40-backend-deployment.yaml` and `50-frontend-deployment.yaml` to the Docker Hub images you pushed. The current examples use `vikrant9850/cheapkart-backend:1.0` and `vikrant9850/cheapkart-frontend:1.0`.
2. Make sure `backend/.env` contains **production** values, not development placeholders. It is read by `create-backend-secret.sh` and sent to the cluster as a Kubernetes Secret; the values are not printed or written into this folder. The secret contains every variable in that `.env` file.
3. Set a strong `ADMIN_PASSWORD` and `JWT_SECRET`; rotate any development credentials before deployment. `MONGODB_URI` must use the `cheapkart` database and allow network access from the EKS VPC/NAT egress IPs. Solace must be reachable from the worker subnets. SES credentials/sender must be valid in `ap-south-1` (or configure the correct AWS region).

The frontend image needs to be rebuilt after the Nginx/API relative-path change in this repository. Build it without a public API URL, for example:

```sh
docker build --build-arg VITE_API_URL= -t cheapkart-frontend:<tag> ./frontend
```

The backend image can be built from `./backend`. Push both images to Docker Hub before applying the Deployment manifests. Build images for `linux/amd64` for the current EKS worker nodes. Do not put `.env` values or AWS credentials in the image or a tracked YAML file.

For Argo CD automated sync, see [`../argocd/README.md`](../argocd/README.md). Create `cheapkart-backend-secrets` before the first sync; the secret is intentionally not committed to Git.

## Apply order

From the repository root:

```sh
kubectl apply -f kubernetes_manifests/00-namespace.yaml
bash kubernetes_manifests/create-backend-secret.sh
kubectl apply -f kubernetes_manifests/10-configmap.yaml
kubectl apply -f kubernetes_manifests/20-backend-service.yaml
kubectl apply -f kubernetes_manifests/30-frontend-service.yaml
kubectl apply -f kubernetes_manifests/40-backend-deployment.yaml
kubectl apply -f kubernetes_manifests/50-frontend-deployment.yaml
```

Check rollout and the public load balancer hostname:

```sh
kubectl get pods,svc -n cheapkart -o wide
kubectl rollout status deployment/cheapkart-backend -n cheapkart
kubectl rollout status deployment/cheapkart-frontend -n cheapkart
```

Once `cheapkart-frontend` has an external hostname, create a DNS record for your domain pointing to that hostname. This basic Service exposes HTTP only. For HTTPS, add an ACM certificate and configure TLS using an AWS Load Balancer Controller/Ingress or an HTTPS-capable load balancer.

## Operational notes

- Secret values are stored in the cluster as a Kubernetes Secret. For production, prefer AWS Secrets Manager with EKS Pod Identity/Secrets Store CSI Driver. The current EKS Terraform does not configure that integration.
- The current backend Docker health check requires MongoDB connectivity. Kubernetes probes use `/api/health`; the app only starts listening after MongoDB initialization.
- `kubectl apply` only deploys workloads. It does not build images, create ECR repositories, provision MongoDB/ Solace, or configure domain DNS/TLS.
