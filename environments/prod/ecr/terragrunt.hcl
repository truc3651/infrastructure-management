include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules/ecr"
}

inputs = {
  service_list = [
    "backend_users_management",
    "backend_posts_management"
 ]
}
