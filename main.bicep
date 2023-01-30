param location string = resourceGroup().location

param appGw_name string = 'appgw-${location}-001'
param containerApp_name string = 'aca-app-${location}-001'
param containerApps_env_name string = 'aca-env-${location}-001'
param nsg_aca_name string = 'nsg-snet-containerapps-${location}-001'
param nsg_appGw_name string = 'nsg-snet-gw-${location}-001'
//TODO: make dnsZone name dynamic
param privateDnsZone_name string = ''
param pip_appGw_name string = 'pip-appgw-${location}-001'
param vnet_name string = 'vnet-${location}-001'
param snet_aca_name string = 'snet-container-apps'
param snet_appGw_name string = 'snet-gw'
param log_workspace_name string = 'log-workspace-${location}-001'

// resource privateDnsZone_resource 'Microsoft.Network/privateDnsZones@2018-09-01' = {
//   location: 'global'
//   name: aca_env_fqdn
// }

// resource Microsoft_Network_privateDnsZones_A_privateDnsZones_purplefield_d7bf25e8_westeurope_azurecontainerapps_io_name 'Microsoft.Network/privateDnsZones/A@2018-09-01' = {
//   parent: privateDnsZone_resource
//   name: '*'
//   properties: {
//     aRecords: [
//       {
//         ipv4Address: '10.0.0.152'
//       }
//     ]
//     ttl: 3600
//   }
// }

// resource privateDnsZone_link_resource 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
//   parent: privateDnsZone_resource
//   location: 'global'
//   name: 'vnet-link-aca'
//   properties: {
//     registrationEnabled: true
//     virtualNetwork: {
//       id: vnet_resource.id
//     }
//   }
// }

resource log_workspace_resource 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  location: location
  name: log_workspace_name
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource containerApp_resource 'Microsoft.App/containerapps@2022-10-01' = {
  name: containerApp_name
  location: location
  properties: {
    configuration: {
      ingress: {
        allowInsecure: true
        external: true
        targetPort: 80
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    managedEnvironmentId: containerApps_env_resource.id
    template: {
      containers: [
        {
          name: containerApp_name
          image: 'mcr.microsoft.com/azuredocs/azure-vote-front:v1'
          env: [
            {
              name: 'REDIS'
              value: 'localhost'
            }
          ]
          resources: {
            cpu: json('.25')
            memory: '.5Gi'
          }
        }
        {
          name: 'redis'
          image: 'mcr.microsoft.com/oss/bitnami/redis:6.0.8'
          env: [
            {
              name: 'ALLOW_EMPTY_PASSWORD'
              value: 'yes'
            }
          ]
          resources: {
            cpu: json('.25')
            memory: '.5Gi'
          }
        }
      ]
      revisionSuffix: 'firstrevision'
      scale: {
        maxReplicas: 3
        minReplicas: 1
        rules: [
          {
            name: 'http-requests'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

resource containerApps_env_resource 'Microsoft.App/managedEnvironments@2022-10-01' = {
  location: location
  name: containerApps_env_name
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: log_workspace_resource.properties.customerId
        sharedKey: log_workspace_resource.listKeys().primarySharedKey
      }
    }
    customDomainConfiguration: {
    }
    vnetConfiguration: {
      // dockerBridgeCidr: '10.2.0.1/16'
      infrastructureSubnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet_name, snet_aca_name)
      internal: true
      outboundSettings: {
        outBoundType: 'LoadBalancer'
      }
      // platformReservedCidr: '10.1.0.0/16'
      // platformReservedDnsIP: '10.1.0.2'
    }
    zoneRedundant: false
  }
  sku: {
    name: 'Consumption'
  }
}

resource appGw_resource 'Microsoft.Network/applicationGateways@2022-07-01' = {
  location: location
  name: appGw_name
  properties: {
    autoscaleConfiguration: {
      maxCapacity: 2
      minCapacity: 1
    }
    backendAddressPools: [
      {
        name: 'bp-aca-env'
        properties: {
          backendAddresses: [
            {
              fqdn: containerApp_resource.properties.configuration.ingress.fqdn
            }
          ]
        }
      }
      {
        name: 'deny-pool'
        properties: {
          backendAddresses: []
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'be-settings-aca'
        properties: {
          affinityCookieName: 'ApplicationGatewayAffinity'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          port: 80
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', appGw_name, 'be-probe')
          }
          protocol: 'Http'
          requestTimeout: 20
        }
      }
    ]
    backendSettingsCollection: []
    enableHttp2: false
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: pip_appGw_resource.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
    ]
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet_name, 'snet-gw')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'http-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGw_name, 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGw_name, 'port_80')
          }
          hostNames: []
          protocol: 'Http'
          requireServerNameIndication: false
        }
      }
    ]
    listeners: []
    loadDistributionPolicies: []
    privateLinkConfigurations: []
    probes: [
      {
        name: 'be-probe'
        properties: {
          interval: 30
          match: {
            statusCodes: [
              '200-399'
            ]
          }
          minServers: 0
          path: '/'
          pickHostNameFromBackendHttpSettings: true
          protocol: 'Http'
          timeout: 30
          unhealthyThreshold: 3
        }
      }
    ]
    redirectConfigurations: []
    requestRoutingRules: [
      {
        name: 'rule-default'
        properties: {
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGw_name, 'http-listener')
          }
          priority: 100
          ruleType: 'PathBasedRouting'
          urlPathMap: {
            id: resourceId('Microsoft.Network/applicationGateways/urlPathMaps', appGw_name, 'rule-default')
          }
        }
      }
    ]
    rewriteRuleSets: []
    routingRules: []
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
    }
    sslCertificates: []
    sslProfiles: []
    trustedClientCertificates: []
    trustedRootCertificates: []
    urlPathMaps: [
      {
        name: 'rule-default'
        properties: {
          defaultBackendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGw_name, 'bp-aca-env')
          }
          defaultBackendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGw_name, 'be-settings-aca')
          }
          pathRules: [
            {
              name: 'deny-route'
              properties: {
                backendAddressPool: {
                  id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGw_name, 'deny-pool')
                }
                backendHttpSettings: {
                  id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGw_name, 'be-settings-aca')
                }
                paths: [
                  '/deny'
                ]
              }
            }
            {
              name: 'default-route'
              properties: {
                backendAddressPool: {
                  id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGw_name, 'bp-aca-env')
                }
                backendHttpSettings: {
                  id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGw_name, 'be-settings-aca')
                }
                paths: [
                  '/*'
                ]
              }
            }
          ]
        }
      }
    ]
  }
}

resource pip_appGw_resource 'Microsoft.Network/publicIPAddresses@2022-07-01' = {
  location: location
  name: pip_appGw_name
  properties: {
    dnsSettings: {
      domainNameLabel: 'aca-gw'
    }
    idleTimeoutInMinutes: 4
    ipTags: []
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
}

resource nsg_aca_resource 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {
  location: location
  name: nsg_aca_name
  properties: {
    securityRules: []
  }
}

resource nsg_appGw_resource 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {
  location: location
  name: nsg_appGw_name
  properties: {
    securityRules: [
      {
        name: 'GatewayManager'
        properties: {
          access: 'Allow'
          destinationAddressPrefix: '*'
          destinationAddressPrefixes: []
          destinationPortRange: '65200-65535'
          destinationPortRanges: []
          direction: 'Inbound'
          priority: 100
          protocol: '*'
          sourceAddressPrefix: 'GatewayManager'
          sourceAddressPrefixes: []
          sourcePortRange: '*'
          sourcePortRanges: []
        }
        type: 'Microsoft.Network/networkSecurityGroups/securityRules'
      }
      {
        name: 'AllowAnyHTTPInbound'
        properties: {
          access: 'Allow'
          destinationAddressPrefix: '*'
          destinationAddressPrefixes: []
          destinationPortRange: '80'
          destinationPortRanges: []
          direction: 'Inbound'
          priority: 120
          protocol: 'TCP'
          sourceAddressPrefix: '*'
          sourceAddressPrefixes: []
          sourcePortRange: '*'
          sourcePortRanges: []
        }
        type: 'Microsoft.Network/networkSecurityGroups/securityRules'
      }
    ]
  }
}

resource vnet_resource 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  location: location
  name: vnet_name
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    dhcpOptions: {
      dnsServers: []
    }
    enableDdosProtection: false
    subnets: [
      {
        name: snet_aca_name
        properties: {
          addressPrefix: '10.0.0.0/21'
          delegations: []
          networkSecurityGroup: {
            id: nsg_aca_resource.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          serviceEndpoints: []
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
      {
        name: snet_appGw_name
        properties: {
          addressPrefix: '10.0.8.0/24'
          applicationGatewayIpConfigurations: [
            {
              id: resourceId('Microsoft.Network/applicationGateways/gatewayIPConfigurations', appGw_name, 'appGatewayIpConfig')
            }
          ]
          delegations: []
          networkSecurityGroup: {
            id: nsg_appGw_resource.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          serviceEndpoints: []
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
    ]
    virtualNetworkPeerings: []
  }
}

output containerAppFQDN string = containerApp_resource.properties.configuration.ingress.fqdn
