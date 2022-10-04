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
    }
  }
}

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
