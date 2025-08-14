##
# (c) 2021-2025
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

variable "settings" {
  description = "Settings for the EFS module, including file system configuration and mount targets."
  type        = any
  default     = {}
}