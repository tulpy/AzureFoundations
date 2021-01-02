# Deploy Enterprise-Scale with hub and spoke architecture

| Reference Implementation | Description | ARM Template | Link |
|:-------------------------|:-------------|:-------------|------|
| Perth | Platform subscription deployment for Identity, Management and Networking resources (Traditional Hub & Spoke deployment pattern) |[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#blade/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftulpy%2FAzureFoundations%2FMaster%2Freference%2Fperth%2FarmTemplates%2Fhub.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Ftulpy%2FAzureFoundations%2FMaster%2Freference%2Fperth%2FarmTemplates%2Fportal-hub.json) | [Detailed description](./reference/perth/README.md) |

The Enterprise-Scale architecture is modular by design and allow organizations to start with foundational landing zones that support their application portfolios and add hybrid connectivity with ExpressRoute or VPN when required. Alternatively, organizations can start with an Enterprise-Scale architecture based on the traditional hub and spoke network topology if customers require hybrid connectivity to on-premises locations from the begining.  

## Customer profile

This reference implementation is ideal for customers that have started their Enterprise-Scale journey with an Enterprise-Scale foundation implementation and then there is a need to add connectivity on-premises datacenters and branch offices by using a traditional hub and spoke network architecture. This reference implementation is also well suited for customers who want to start with Landing Zones for their net new
deployment/development in Azure by implementing a network architecture based on the traditional hub and spoke network topology.

## How to evolve from Enterprise-Scale foundation

If customer started with a Enterprise-Scale foundation deployment, and if the business requirements changes over time, such as migration of on-premise applications to Azure that requires hybrid connectivity, you will simply create the **Connectivity** Subscription, place it into the **Platform > Connectivity** Management Group and assign Azure Policy for the hub and spoke network topology.

## Pre-requisites

To deploy this ARM template, your user/service principal must have Owner permission at the Tenant root.
See the following [instructions](https://docs.microsoft.com/en-us/azure/role-based-access-control/elevate-access-global-admin) on how to grant access.

### Optional prerequisites

The deployment experience in Azure portal allows you to bring in existing (preferably empty) subscriptions dedicated for platform management, connectivity and identity. It also allows you to bring existing subscriptions that can be used as the initial landing zones for your applications.

To learn how to create new subscriptions programatically, please visit this [link](https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/programmatically-create-subscription?tabs=rest).

To learn how to create new subscriptions using Azure portal, please visit this [link](https://azure.microsoft.com/en-us/blog/create-enterprise-subscription-experience-in-azure-portal-public-preview/).

## What will be deployed?

The following resources have been provisioned as part of the deployment.

* A scalable Management Group hierarchy aligned to core platform capabilities, allowing Silver Chain to operationalize at scale using centrally managed Azure RBAC and Azure Policy where platform and workloads have clear separation.
* Azure Policies that will enable autonomy for the platform and the landing zones.
* An Azure subscription dedicated for the **platform**, which enables core platform capabilities across Identity, Networking and Management services, such as:
  * A Log Analytics workspace and an Automation account
  * Azure Security Center monitoring
  * Azure Security Center (Free tier)
  * Diagnostics settings for Activity Logs, VMs, and PaaS resources sent to Log Analytics
  * A hub virtual network and associated subnets
  * Network Security Groups assigned to all subnets
  * User Define Routes to redirect traffic to the Azure Firewall
  * Azure Firewall
  * ExpressRoute Gateway
* Application Landing Zone Management Group for **production** and **non-production** applications that require connectivity to on-premises, to other landing zones or to the internet via shared services provided in the hub virtual network.
* Azure Policies for **production** and **non-production** landing zones, which include:
  * Enforce VM monitoring (Windows & Linux)
  * Enforce secure access (HTTPS) to storage accounts
  * Prevent IP forwarding
  * Prevent inbound SSH from internet
  * Prevent inbound RDP from internet
  * Prevent Public IP addresses
  * Prevent Public endpoints for all Azure PaaS services
  * Ensure subnets are associated with NSG
  * Appending environment tags to all resources

![Enterprise-Scale with connectivity](./media/es-hubspoke.png)
