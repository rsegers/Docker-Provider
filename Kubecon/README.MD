# Kubecon Azure Monitor for containers lab

## Overview

### This Azure Monitor for containers lab will give you hands on experience to monitor AKS workloads. In this lab you will be working Azure Monitor, Log Analytics and Azure Monitor for Container Insights.

## Instructions for lab

1. Set-up environment [Setup Guide](https://github.com/rkuehfus/pre-ready-2019-H1/blob/master/Student/Guides/Deployment%20Setup%20Guide.docx?raw=true)

2. Tasks for the lab
  *  From your Visual Studio Server, deploy the eShoponWeb application to AKS using Dev Spaces
  *  From Azure Monitor, locate the container running the eShoponWeb application
  *  Generate an exception in the eShoponWeb application(Hint: Try to change your password)
  *  Optimize the Azure Monitor for contains ingestion cost by fine tuning log-collection parameters like std-out/std-error, namespace.

## Outcome

### Understand Azure Monitor capabilities, facilitate an Azure Monitor customer conversation, and demo key features of Azure Monitor.

## Target Audience

This content has been targeted to devops/SRE intended to build their knowledge on Azure Monitor also for people that have a passion around Monitoring are more than welcome to attend.

## Prerequisites
 1.	Please review the following content before the event
  a.  [Azure Monitor for containers Overview](https://docs.microsoft.com/azure/azure-monitor/insights/container-insights-overview)
  b.  [Optimize Azure Monitor for containers cost ](https://medium.com/microsoftazure/azure-monitor-for-containers-optimizing-data-collection-settings-for-cost-ce6f848aca32)

2.	Attendees have access to an Azure Subscription where they can each deploy the provided ARM template that will build a very detailed infrastructure to monitor.  This includes the Vnet, subnets, NSG(s), LB(s), NAT rules, scales set and a fully functional .NET Core Application (eShopOnWeb) to monitor.
3.	Attendees should have a level 200-300 understanding of the Azure platform.  Understand concepts like PowerShell, Azure Cli, ARM, resource groups, RBAC, network, storage, compute, scale sets, virtual machines and security.  Previous experience working with ARM templates is recommended.
4.	Access to a machine with Visual Studio Code and the Azure PowerShell Modules loaded or Azure CLI. VS Code ARM and PowerShell extensions should be configured.

![alt text](https://raw.githubusercontent.com/rkuehfus/pre-ready-2019-H1/master/monitoringhackdiagram.png)


