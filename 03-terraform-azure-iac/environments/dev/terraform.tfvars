# Dev environment overrides
# Override any variable from variables.tf here.
# aws_region and environment are set via TF_VAR_* in setup.sh.

instance_type    = "t3.micro"
min_size         = 1
max_size         = 2
desired_capacity = 1   # Keep costs low in dev; scale up to test ASG behaviour
