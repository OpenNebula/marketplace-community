variable "appliance_name" {
  type    = string
  default = "phoenix"
}

variable "input_dir" {
  type = string
  default = "./"
}

variable "output_dir" {
  type = string
  default = "./build/service_phoenix"
}

variable "headless" {
  type    = bool
  default = false
}

variable "version" {
  type    = string
  default = ""
}
