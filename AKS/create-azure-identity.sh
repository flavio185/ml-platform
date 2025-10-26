
# Defina suas variáveis (substitua pelos seus valores)
../.env
# Crie a Aplicação no Azure AD
APP_REGISTRATION=$(az ad app create --display-name "GitHub Actions for ${AKS_CLUSTER_NAME}")
export CLIENT_ID=$(echo $APP_REGISTRATION | jq -r '.appId')

# Crie o Service Principal para a aplicação
az ad sp create --id $CLIENT_ID

# Obtenha o ID do seu Tenant
export TENANT_ID=$(az account show --query tenantId -o tsv)

# 2. Atribua a Permissão para o Service Principal no seu Cluster AKS:
az role assignment create \
  --role "Azure Kubernetes Service RBAC Writer" \
  --assignee $CLIENT_ID \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ContainerService/managedClusters/${AKS_CLUSTER_NAME}"

# 3. Crie um Segredo no GitHub com o Client ID, Tenant ID e Subscription ID:
az ad app federated-credential create \
  --id $CLIENT_ID \
  --parameters '{
    "name": "github-actions-federated-credential",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"${GITHUB_ORG_OR_USER}"/"${GITHUB_REPO}"':ref:refs/heads/main",
    "description": "GitHub Actions OIDC connection",
    "audiences": [
      "api://AzureADTokenExchange"
    ]
  }'

# Adicionar Client ID, Tenant ID e Subscription ID como segredos no GitHub
gh secret set AZURE_CLIENT_ID --body "$CLIENT_ID" --repo "${GITHUB_ORG_OR_USER}/${GITHUB_REPO}"
gh secret set AZURE_TENANT_ID --body "$TENANT_ID" --repo "${GITHUB_ORG_OR_USER}/${GITHUB_REPO}"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID" --repo "${GITHUB_ORG_OR_USER}/${GITHUB_REPO}"
echo "✅ Azure Identity and GitHub Secrets setup completed." | tee -a "$OUTPUT_FILE"

#DEBUG:
az login --service-principal -u $CLIENT_ID  --tenant $TENANT_ID
az account show
az role assignment create \
  --assignee $CLIENT_ID \
  --role Contributor \
  --scope /subscriptions/$SUBSCRIPTION_ID