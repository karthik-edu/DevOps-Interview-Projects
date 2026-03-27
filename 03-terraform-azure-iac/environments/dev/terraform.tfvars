# Dev environment overrides
# Override any variable from variables.tf here.
# location, environment, and ssh_public_key are set via TF_VAR_* in setup.sh.

vm_size          = "Standard_B1s"   # ~t3.micro equivalent, keep costs low in dev
min_size         = 1
max_size         = 3
desired_capacity = 1                # Scale up to test autoscale behaviour
