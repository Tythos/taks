The cloud is a nuisance. "Someone else's computer" is the common description--but if it was really just "someone else's computer" it would be a lot simpler to learn and manage!

## Introduction

This is particularly the case if you come from what I call a "constructive" background when approaching orchestration. You have a container here, a container there, and maybe a database & front-end, but docker-compose isn't hacking it anymore and you know you need to grow up & join the big boys, out there on the cloud. But it's a lot.

Fortunately, there are some great tools to help you out. Unfortunately, there are *waaaaaaaaaaay* too many of them, and the population doubles every time you turn your back. It's not even clear where the lines between one family of tools ends and another begins--do you really need JFrog if you have GitLab? What's the difference between Zarf and Rancher again? And, dear God, is it even possible to get away with avoiding AWS? (Spoiler: yes.)

This headache makes it a *very* nice experience when you actually DO run into tools that complement each other in a way that makes cloud engineering (and development) a pleasant and relatively pain-free experience. One such stack I've found to be very useful, particularly for agnostic deployments, is "TAKS": Terraform AKS (the Azure Kubernetes Service). Here's how you can get it running.

## Terraform

Terraform is the quintessential infrastructure-as-code tool. It's theoretically agnostic (more on that later) and comes with a large library of support for different "providers" (integration targets). Architects define infrastructure in a static, declarative format--combining provider-defined resources and integrating them with variables across reusable modules.

> *(Note that commands in this section are presented for purposes of demonstrating the Terraform workflow; we haven't written anything yet so they won't do anything. Commands and file content in subsequent sections can, and should, be used!)*

### Workflow

The Terraform process itself nicely encapsulates how it helps you manage infrastructure abstractions:

* First, you define your infrastructure in declarative .TF files

* Then, you initialize your Terraform environment to install and integrate the necessary provider and module dependencies:

```
> terraform init
```

* You can then tell Terraform to review your .TF-defined infrastructure; this "desired state" is compared to the "actual state" and a "plan" is created to move from the former to the latter.

```
> terraform plan
```

* Finally, you ask Terraform to "apply" the plan; it gets to work and makes the appropriate changes to your infrastructure to realize the desired end state.

```
> terraform apply
```

## Advantages

This is a *really* nice way to interact with cloud providers. Otherwise you are typically left with wrestling in obscure CLIs, random shell scripts, or spinning up your own VMs directly within the provider's dashboard. Not that those are bad ways to experiment--but Terraform gives you the tools to do so formally, in a way that even lets you check .TF files into GitLab/GitHub projects and change-control your infrastructure as part of a CI/CD pipeline. *Nooooice.*

Terraform is pretty easy to install, and is typically distributed as a single executable. I drop it in my tools folder (exposed on PATH) and I'm good to go.

## Azure

I don't know about you, but I avoid AWS as much as I can. They were first, and they're still the biggest. But as a result, they have their own way of approaching provisioning, and their own infrastructure abstractions (not to mention cost models), which pretty much guarantees once you go AWS (or if you learn it first) you are "locked in".

As a result--and as much as I love Google in general, their work on individual cloud technologies has greatly outpaced the capabilities and maturity of their own cloud services--Azure is my go-to cloud provider. (There are other second-tier providers, of course, like DigitalOcean or DreamHost, which are largely OpenStack-based, but I won't dive into detailed comparisons here.) Suffice it to say, you are more likely to hew to an agnostic infrastructure (and more likely to leverage enterprise-grade reliability & maturity) if you start with Azure.

If you don't have an Azure account, there are plenty of free credit offers available. What we're spinning up here needs a Kubernetes-class VM to host the cluster, which isn't free (and doesn't use the absolute cheapest VMs), but it is still pretty cost-effective and (until recently, sort-of) is actually easier and more transparent to use for K8s, with some nice built-in tooling.

### Azure Commands

Once you are signed up, you'll need to call the CLI for a couple of key account fields:

* First, look up your subscription information to reference later on when defining the service principal's scope. From the resulting JSON structure, you will want to find the entry for which "isDefault" is true, and store the corresponding "id" field as the environmental variable "SUBSCRIPTION_ID".

```
> az account list > subscriptions.json
```

* Second, create a "service principal", the Azure user acting on Terraform's behalf. From the resulting JSON structure, you will want to store the "appId" field as the environmental variable "SP_ID" and the "password" field as the environmental variable "SP_SECRET".

```
> az ad sp create-for-rbac --skip-assignment --name my-service-principal > ad_sp.json
```

* Next, assign that service principal "Contributor" privileges to perform the actions it needs. You should already have environmental variables "%SP_ID%" and "%SUBSCRIPTION_ID%" assigned from previous steps.

```
> az role assignment create --assignee %SP_ID% --scope "/subscriptions/%SUBSCRIPTION_ID%" --role Contributor > role_assignment.json
```

### Key Generation

Lastly, we need to generate an SSH key pair with which we (and any other actors, such as Terraform) can use to authenticate against the systems we create. After this command has run, assign the contents of the public key ("id_rsa.pub"), which should be a single-line string beginning with "ssh-rsa ...", to the environmental variable "SSH_KEY".

```
> ssh-keygen -t rsa -b 4096 -f ".\id_rsa" -N ""
```

Every subsequent Azure interaction can now take place through Terraform itself, which *greatly* simplifies pretty much everything.

## Kubernetes Cluster

Your primary objective here is to define a Kubernetes cluster in Terraform that can then be provisioned on Azure. Create a "providers.tf" file, in which you will define your Terraform version and the providers we will be using:

```tf
terraform {
  required_version = ">=1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~>2.13"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.my-aks-cluster.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.my-aks-cluster.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.my-aks-cluster.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.my-aks-cluster.kube_config.0.cluster_ca_certificate)
}
```

Some interesting notes here:

* Both Azure and Kubernetes are treated by Terraform as just another set of providers. These providers expose resources we can use to define our infrastructure.

* The Kubernetes provider can be defined using properties defined in the Azure resources. This is a *really* nice feature of Terraform--outputs of one resource can be used as inputs to another, effectively automating the "stitching" process that can make infrastructure management such a complicated nightmare.

You can run "terraform init" to install the appropriate dependencies/providers, but we haven't defined any infrastucture yet--so "terraform plan" and "terraform apply" won't do anything useful. Yet!

```
> terraform init
```

### Resource Group

Create a new file, named "cluster.tf". We will be adding to Azure-based resources to this file:

* A "resource group", which is how Azure groups shared resources

* An "AKS", or Azure Kubernetes Service, cluster

The first item goes into your "cluster.tf" like so:

```tf
resource "azurerm_resource_group" "my-aks-rg" {
  name     = "my-aks-rg"
  location = var.location
}
```

The basic Terraform resource declaration goes something like "resource [resource type] [resource name]". This is followed by a block in which you can define specific key-value pairs and additional property blocks. Some of these properties can even be assigned procedurally from other references--like variables (preceded by "var.") that we will define later. So, you might read this content like so:

* "I want to create a new resource of the type 'azurerm_resource_group'"

* "It should have the name 'my-aks-rg'"

* "It will have a 'name' of 'my-aks-rg'"

* "It will have a location whose value will come from the variable 'location'"

### Kubernetes Cluster

That's a simple case, though. Let's look at the AKS resource, which is significantly more complicated:

```tf
resource "azurerm_kubernetes_cluster" "my-aks-cluster" {
  name                = "my-aks-cluster"
  location            = azurerm_resource_group.my-aks-rg.location
  resource_group_name = azurerm_resource_group.my-aks-rg.name
  dns_prefix          = "my-aks-cluster"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name            = "default"
    node_count      = 1
    vm_size         = "Standard_E4s_v3"
    type            = "VirtualMachineScaleSets"
    os_disk_size_gb = 250
  }

  service_principal {
    client_id     = var.serviceprincipal_id
    client_secret = var.serviceprincipal_key
  }

  linux_profile {
    admin_username = "my_admin_username"
    ssh_key {
      key_data = var.ssh_key
    }
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
  }
}
```

Add this resource to your "cluster.tf" file, too. I'll point out some of the more interesting tidbits from this block:

* Properties like "location" and "resource_group_name" reference properties of other resources--in this case, the resource group. This means you can assert identical locations and associations within your infrastructure consistently.

* We define "node_pool" and "service_principal" blocks to indicate, respectively, the template of VMs in our "scale set" to use for nodes, and how the service principal credentials can be used to interact with Azure.

* We can pass the SSH key for the VM systems directly to the provisioning

* We let Azure know in the "network_profile" block that Kubernetes will handle the network configuration, including load-balancing

### Variables

There are several variables we have reference so far. Common practice is to define these in a separate file, or even a unique file for each "module" (e.g., reusable folders of resource templates). For purposes of simplification, we'll consolidate these into the "cluster.tf" file since few are reused across files. Paste the following into the bottom of your "cluster.tf" file:

```tf
variable "location" {
  default = "centralus"
}

variable "kubernetes_version" {
  default = "1.24.3"
}

variable "serviceprincipal_id" {
}

variable "serviceprincipal_key" {
}

variable "ssh_key" {
}
```

You'll notice a few important things:

* We reference these variables in other parts of the Terraform file by preceding their name with "var."

* Some of these variables have default values; others must be specified when Terraform is asked to construct the plan ("terraform plan")

* Variable values can be passed via environmental variable using the command line flags "-var". For example, "terraform plan -var ssh_key=%SSH_KEY%" will use the value of the environmental variable "%SSH_KEY%" for the Terraform variable "ssh_key".

This last item is particularly important; some variables you want to control because they may easily change (like location for Azure provisioning); others (like keys) you want to define at runtime to avoid storing sensitive information.

### Plan and Apply

Now that we've defines a cluster for provisioning, we can ask Terraform to plan the transition:

```
> terraform plan -out tf.plan^
    -var serviceprincipal_id=%SP_ID%^
    -var serviceprincipal_key="%SP_SECRET%"^
    -var ssh_key="%SSH_KEY%"
```

This command forwards environmental variable values and writes out the resulting plan to a "tf.plan" file that subsequent steps can reference. You should see something like the following if the command was successful:

```
Plan: 2 to add, 0 to change, 0 to destroy.

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Saved the plan to: tf.plan

To perform exactly these actions, run the following command to apply:
    terraform apply "tf.plan"
```

This tells you two important pieces of information:

* There are two new resources that will be created--in this case, specifically, the Azure "resource group" and the Azure "Kubernetes service" cluster

* The plan for executing this transformation has been saved to the "tf.plan" file

Now, you can run "terraform apply" with that "tf.plan" file as the primary argument:

```
> terraform apply "tf.plan"
...
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

With that done, you've provisioned a TAKS stack! (Give it a few minutes, provisioning those VMs can be time-consuming on Azure.) Congratulations!

## K8s

We're not done yet, of course. We have a Kubernetes *cluster*, but there is nothing provisioned on it!

At this stage, traditionally, you'd need to learn *kubectl* commands, memorize a bunch of complicated new .YML-based specifications, and maybe massage a Docker compose configuration through the "kompose" transformation (which is a neat tool, but far from ready for prime time). But, we're already working in Terraform! And in Terraform's eyes, the *contents* of the Kubernetes cluster are no different than any other configuration of infrastructure resources.

### Deployment

Create a new, separate Terraform file, "k8s.tf". This file will focus on defining the mesh we provision on our Kubernetes cluster. Paste in the following contents:

```tf
resource "kubernetes_deployment" "my-k8s-deployment" {
  metadata {
    name = "my-k8s-deployment"
    labels = {
      test = "MyK8sApp"
    }
  }

  spec {
    replicas = 3
    selector {
      match_labels = {
        test = "MyK8sApp"
      }
    }

    template {
      metadata {
        labels = {
          test = "MyK8sApp"
        }
      }
    }
  }
}
```

We've started by defining a Kubernetes "deployment"--that is, the pattern with which the cluster will be populated. This is a "resource type" defined by the Kubernetes provider--note we don't even need to bother indicating anything related to Azure! Now that we've provisioned the cluster, every subsequent step will be complete agnostic to our cloud provider. (Damn but Terraform is great.)

### Containers

We've defined a set of labels to map different specifications against each other. This includes the set of pods deployed across our nodes (including how many replicas are required), as well as the template itself. But there's nothing in the template yet! Let's add a specification for a basic container. Paste the following within the "template" block, after the "metadata" block:

```tf
      spec {
        container {
          image = "nginx:1.7.8"
          name  = "my-nginx-container"

          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "50Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/nginx_status"
              port = 80
              http_header {
                name  = "X-Custom-Header"
                value = "Awesome"
              }
            }

            initial_delay_seconds = 3
            period_seconds        = 3
          }
        }
      }
```

There's actually a lot going on here! And you may have noticed by the point, we're basically mapping the Kubernetes .YML structure into a Terraform file. Let's dive into this container declaration a little bit:

* The container we are defining will be instantiated from a particular image. In this case, we're pulling a specific nginx image--which will default to the one hosted on Docker Hub. In production, you will want to maintain your own registry of images (using, for example, the conveniently-defined Azure Container Registry resource), in order to isolate and confine deployment artifacts and credential scopes.

* We've defined a specific set of resource constraints for this container instance. This helps maintain manageable performance, particularly on a constrained VM (which is typically a primary cost driver--more expensive VMs really add up fast). If you need more performance, you typically scale "out" (adding more replicas), rather than "up" (throwing more cycles at the container).

* We've also defined a "probe" by which the container can be monitored. This helps the cluster monitor our resources for health and performance purposes.

### Service

We've defined a minimal Kubernetes deployment, but if you've used Kubernetes before, you know that we still need to expose these services to public requests. The Kubernetes abstraction that manages external network interfacing (including load balancing) is called a "service". (Ignore the fact that "service" is an incredibly overused term--almost as overused as "resource", in fact--that means different things in closely-related contexts.)

Paste the following block at the end of your "k8s.tf" file:

```tf
resource "kubernetes_service" "my-k8s-service" {
  metadata {
    name = "my-k8s-service"
  }

  spec {
    selector = {
      test = "MyK8sApp"
    }
    port {
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
}
```

Again, we've told Terraform that there is another "resource" that is part of our infrastructure; this time, it is of the type "kubernetes_service". This "resource" has the following properties:

* Specific internal ports are mapped to external ports (80:80)

* It applies to a specific deployment, identified by matching labels ("MyK8sApp")

* It performs load balancing at the network interface across our deployment

Now, you are ready to step through the Terraform deployment steps!

```
> terraform plan -out tf.plan^
    -var serviceprincipal_id=%SP_ID%^
    -var serviceprincipal_key="%SP_SECRET%"^
    -var ssh_key="%SSH_KEY%"
> terraform apply "tf.plan"
```

## Conclusion

Congratulations! You've now deployed a Terraform-managed Kubernetes stack on Azure!

In summary: cloud tech can be overwhelming; there's a lot of redundant technologies out there, and it can be difficult to get started. Hopefully, the TAKS stack will help you out by automating and formalizing a lot of your infrastructure headaches, and help you focus on the unique parts of your application/mesh. Piecing it together has been an invaluable exercise for me.

If you've used Kubernetes before, you'll appreciate how much of this process we've managed to automate and defined in a reference specification. If you haven't, know that any future development--including deployment of new services, databases, and network configurations--is an easy delta.

Simply add a container specification to your "k8s.tf" template, mount any stateful volumes (if, for example, you need a Redis appendfile), and expose the appropriate network configuration! Then, run a quick "terraform plan" and "terraform apply" to let the automation take care of the rest. It's the power of Terraform, baby!

### Notes

Some final notes:

* Kubernetes doesn't move too fast. You might need to give it a few minutes before all of your pods have successfully deployed, beyond the point in time when the "terraform apply" command returns/exist.

* You can view the external IP assigned to your service by browsing to "https://portal.azure.com" and looking for the "my-aks-rg" resource group. You'll see the "my-aks-cluster" listed, and when you select it, you can click the "Services and Ingresses" option from the menu on the left. The "my-k8s-service" row should have an "External IP" column that you can click to jump directly to that URL.

* Don't forget to "tear down" your infrastructure before Microsoft places too many charges against your Azure subscription! Look up the "terraform destroy" command to see how this can be done against a specific plan.

* Technically, we aren't *entirely* agnostic to the cloud provider. If you wanted to deploy this on AWS or Google Cloud, you'd need to swap out the contents of "providers.tf" and "cluster.tf" with the appropriate hooks (the former will be much easier than the latter). But, "k8s.tf" will remain the same--and that's where you'll be doing most of your custom architecting anyway.

### Resources

Additional resources? You bet!

* This article has a permanent home on dev.to at https://dev.to/tythos/the-taks-stack-4a2f

* There's a GitHub repository with all of these contents ready-to-go, including this README file: https://github.com/Tythos/taks

* Want to learn more about what other Azure resources you can add to your infrastructure? The official docs are excellent: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs

* Want to learn more about what other Kubernetes resources you can add to your infrastructure? Follow the docs: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
