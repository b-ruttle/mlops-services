path "secret/data/mlops-services/prod/postgres" {
  capabilities = ["read"]
}

path "secret/data/mlops-services/prod/rustfs" {
  capabilities = ["read"]
}

path "secret/data/mlops-services/prod/keycloak" {
  capabilities = ["read"]
}

path "secret/data/mlops-services/prod/oauth2-proxy" {
  capabilities = ["read"]
}

path "secret/data/mlops-services/prod/mlflow" {
  capabilities = ["read"]
}

path "secret/metadata/mlops-services/prod/*" {
  capabilities = ["read", "list"]
}
