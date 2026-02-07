## Description
This project manage AWS infra by using Terraform and Terragrunt which follows GitOps principles

## Set up local development
### Set up AWS backend
```
brew install make
make bootstrap
make get-role-arn
```

### Set up hook pretter
```
brew install pre-commit tflint
cd infrastructure-management
pre-commit install
```

## Tear down local development
```
make destroy-backend
```
