set quiet := true

# folders := "vpc route53 acm ec2 rds eks"
# foldersReversed := "eks rds ec2 acm route53 vpc"
folders := "vpc route53 eks"
foldersReversed := "eks route53 vpc"

default: 
  just --list

init:
  for folder in {{folders}}; do \
    echo "Initializing $folder"; \
    terraform -chdir=infra/$folder init; \
  done

apply:
  for folder in {{folders}}; do \
  echo "Applying $folder"; \
    terraform -chdir=infra/$folder apply --auto-approve; \
  done

destroy:
  for folder in {{foldersReversed}}; do \
    echo "Destroying $folder"; \
    terraform -chdir=infra/$folder destroy --auto-approve; \
  done
