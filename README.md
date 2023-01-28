# Azure Container Apps Demo

[![Build](https://github.com/timoknapp/az-container-apps-demo/actions/workflows/main.yml/badge.svg?branch=master)](https://github.com/timoknapp/az-container-apps-demo/actions/workflows/main.yml)

Simple demo to showcase Azure Container Apps

## Prerequisites

In order to run the demo you need to have the following tools installed:

* [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)

Make sure that you have the latest version of the Azure CLI installed:

```bash
az --version
```

Make sure you are logged in to your Azure subscription:

```bash
az login
```

## Getting Started

### Deploy

```bash
RG_NAME=rg-container-apps-demo-001
# Create Resource Group
az group create --name $RG_NAME --location westeurope
# Deploy Bicep template
az deployment group create -n az-container-apps-demo --resource-group $RG_NAME --template-file main.bicep
# Setup private DNS Zone
ACA_ENV_FQDN=$(az containerapp env list -g $RG_NAME --query "[0].properties.defaultDomain" -o tsv)
VNET=$(az network vnet list -g $RG_NAME --query "[0].name" -o tsv)
az network private-dns zone create -g $RG_NAME -n $ACA_ENV_FQDN
az network private-dns link vnet create -g $RG_NAME -n "aca-dns-link" -z $ACA_ENV_FQDN -v $VNET -e true
```

### Cleanup Resource Group

```bash
az group delete --name rg-container-apps-demo-001 --yes
```
