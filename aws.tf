provider "aws" {
  region = var.ASG_Region
  profile = "Aditya-demo"
}
resource "aws_ami_from_instance" "autoscaling" {
  name               = "${var.ASG_NAME}-${var.DATE}"
  source_instance_id = "${var.INSTANCE_ID}"
}

output "autoscaling_id" {
  value = "${aws_ami_from_instance.autoscaling.id}"
}
variable "ASG_Region" {
}
# variable "ASG_NAME" {
#   }
variable "DATE" {
  }
variable "INSTANCE_ID" {
 }