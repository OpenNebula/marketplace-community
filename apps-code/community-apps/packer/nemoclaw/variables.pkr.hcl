variable "appliance_name" {
  type    = string
  default = "nemoclaw"
}

variable "version" {
  type    = string
  default = "0.1.0"
}

variable "input_dir" {
  type    = string
  default = "packer/nemoclaw"
}

variable "output_dir" {
  type    = string
  default = "output"
}

variable "headless" {
  type    = bool
  default = true
}
