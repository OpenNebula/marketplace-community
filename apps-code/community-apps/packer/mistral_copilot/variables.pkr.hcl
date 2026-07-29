variable "appliance_name" {
  type    = string
  default = "mistral_copilot"
}

variable "version" {
  type    = string
  default = "2.7.0"
}

variable "input_dir" {
  type    = string
  default = "packer/mistral_copilot"
}

variable "output_dir" {
  type    = string
  default = "output"
}

variable "headless" {
  type    = bool
  default = true
}
