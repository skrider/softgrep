variable "region" {
  description = "AWS region"
  type        = string
}

variable "env" {
  description = "App environment (staging, prod) specified via TF_VAR_"
  type        = string
}

