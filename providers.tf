terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider apuntado a LocalStack.
# Las credenciales son ficticias y el endpoint es local: ninguna peticion
# puede llegar a una cuenta real de AWS aunque exista una configurada.
provider "aws" {
  region     = "us-east-1"
  access_key = "test"
  secret_key = "test"

  # Sin estos saltos, Terraform intentaria validar la identidad contra AWS real.
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  # LocalStack resuelve los buckets por ruta, no por subdominio.
  s3_use_path_style = true

  endpoints {
    s3 = "http://localhost:4566"
  }
}
