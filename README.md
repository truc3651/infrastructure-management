## Description
This project manage AWS infra by using Terraform and Terragrunt which follows GitOps principles

## Set up local development
```
brew install make
make bootstrap
make get-role-arn
```

## Tear down local development
```
make destroy-backend
```

## Reason choose Terragrunt
- Centralize backend remote state, provider and common used env
- Graph dependencies instead of managing them in CI/CD pipeline