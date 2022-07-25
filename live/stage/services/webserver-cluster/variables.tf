variable "db_remote_state_bucket" {
  description = "The name of the S3 bucket for the database's remote state"
  type        = string
  default = "tf-up-and-running-state-jm"
}

variable "db_remote_state_key" {
  description = "The path for the database's remote state in S3"
  type        = string
  default = "stage/data-stores/mysql/terraform.tfstate"
}

variable "enable_autoscaling" {
  type = bool
  description = "If set to true, enable auto scaling"
  default = false
}
