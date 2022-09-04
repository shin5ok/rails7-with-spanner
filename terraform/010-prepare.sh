terraform init
terraform providers lock -platform=darwin_amd64 -platform=linux_amd64



# GOPATH=~/go
# # https://github.com/hashicorp/terraform-provider-google
# mkdir -p $GOPATH/src/github.com/hashicorp; cd $GOPATH/src/github.com/hashicorp
# git clone git@github.com:hashicorp/terraform-provider-google
# cd $GOPATH/src/github.com/hashicorp/terraform-provider-google
# make build
