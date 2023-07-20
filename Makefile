PYTHON_ENV = PYTHONPATH="$(CWD):${PYTHONPATH}" \
	LD_LIBRARY_PATH="${NIX_LD_LIB}"
PYTHON_EXE = venv/bin/python
PYTHON = $(PYTHON_ENV) $(PYTHON_EXE)

# BUILD
OUT = $(shell pwd)/build

pb: pb/softgrep.proto
	$(PYTHON) -m grpc_tools.protoc \
		-Ipb --python_out=pb --pyi_out=pb --grpc_python_out=pb pb/softgrep.proto
	protoc --go_out=. --go_opt=paths=source_relative \
		--go-grpc_out=. --go-grpc_opt=paths=source_relative \
		pb/softgrep.proto
.PHONY: pb

# CLI
BENCH_LOG = $(OUT)/benchmark.log
BENCH_CMD = $(OUT)/softgrep ./testdata/grpc
languages: tool/generate_ts_import
	go run tool/generate_ts_import/main.go > pkg/tokenize/languages.go

build-debug:
	go build -o $(OUT)/softgrep-debug -gcflags='all=-N -l' cmd/softgrep/main.go

debug:
	dlv exec $(out)/softgrep-debug

run: 
	go run cmd/softgrep/main.go

format:
	fd -e go -x go fmt
	fd -e py | $(PYTHON_ENV) xargs $(PYTHON_EXE) -m black

build:
	go build -o $(OUT)/softgrep cmd/softgrep/main.go 
.PHONY: build

# message is passed in via env
benchmark: build
	echo --- >> $(BENCH_LOG)
	echo $(MESSAGE) >> $(BENCH_LOG)
	git rev-parse HEAD >> $(BENCH_LOG)
	echo $(BENCH_CMD): >> $(BENCHLOG)
	time --append --output=$(BENCH_LOG) $(BENCHCMD)
	cat $(BENCH_LOG) | tail -n 5

# SERVER
run-server:
	$(PYTHON_ENV) venv.server/bin/python python/server/main.py

server:
	docker buildx build . -t $(LOCAL_TAG)

# DEPLOY
DEPLOY_ARTIFACTS = ./deploy/artifacts/$(DEPLOY_ENV)
DEPLOY_ENV = $(if $(SOFTGREP_ENV),$(SOFTGREP_ENV),development)
AWS_REGION = us-west-2
AWS_ACCOUNT = $(shell aws sts get-caller-identity --query Account --output text)
CLUSTER_NAME = softgrep-$(DEPLOY_ENV)

# SERVER
LOCAL_TAG = softgrep/server
SERVER_ARTIFACTS = $(DEPLOY_ARTIFACTS)/server
ECR_JSON = $(SERVER_ARTIFACTS)/ecr-create-repository.json
SERVER_ECR_REPO = $(shell cat $(ECR_JSON) | jq --raw-output .repository.repositoryUri)
ecr-create:
	mkdir -p $(SERVER_ARTIFACTS)
	aws ecr create-repository \
		--repository-name softgrep/server \
		--no-cli-pager | tee $(ECR_JSON)

ecr-login:
	aws ecr get-login-password --region $(AWS_REGION) \
		| docker login \
			--username AWS \
			--password-stdin $(shell cat $(ECR_JSON) | jq .repository.repositoryUri)

ecr-publish:
	docker tag $(LOCAL_TAG):latest $(shell cat $(ECR_JSON) | jq --raw-output .repository.repositoryUri):latest
	docker push $(SERVER_ECR_REPO):latest

# CLUSTER
CLUSTER_ARTIFACTS=$(DEPLOY_ARTIFACTS)/cluster
EKS_CONFIG_FILE = deploy/cluster.$(DEPLOY_ENV).yaml
EKS_CONFIG = cat $(EKS_CONFIG_FILE) \
		| CLUSTER_NAME=$(CLUSTER_NAME) AWS_REGION=$(AWS_REGION) envsubst
HELM_VALUES = ./deploy/chart/values.$(DEPLOY_ENV).yaml
HELM_ENV = IMAGE_REPOSITORY=$(SERVER_ECR_REPO)
HELM_TEMPLATE = cat $(HELM_VALUES) \
	| $(HELM_ENV) envsubst \
	| helm template softgrep deploy/chart --skip-crds --values -

template:
	$(HELM_TEMPLATE)

vpc:
	aws ec2 create-vpc \
	  --cidr-block "10.0.0.0/16" \
	  --profile default \
	  --region $(AWS_REGION) \
	  | tee $(DEPLOY_ARTIFACTS)/create-vpc.json

VPC=$(shell jq .Vpc.VpcId $(DEPLOY_ARTIFACTS)/create-vpc.json)

vpc-delete:
	aws ec2 delete-vpc --vpc-id $(VPC)

KOPS_USER=kops
kops-user:
	aws iam create-user --user-name $(KOPS_USER)

kops-configure-user:
	aws iam delete-policy
	aws iam create-policy \
		--policy-name KopsPolicy \
		--policy-document file://$(CLUSTER_ARTIFACTS)/kops-role.json \
		| tee $(CLUSTER_ARTIFACTS)/create-policy.json
	aws iam attach-user-policy \
		--policy-arn arn:aws:iam::$(AWS_ACCOUNT):policy/KopsPolicy \
		--user-name $(KOPS_USER)

kops-update-policy:
	aws iam create-policy-version \
		--policy-arn arn:aws:iam::$(AWS_ACCOUNT):policy/KopsPolicy \
		--policy-document file://$(CLUSTER_ARTIFACTS)/kops-role.json \
		--set-as-default

kops-access-key:
	aws iam create-access-key --user-name $(KOPS_USER) \
		| tee $(CLUSTER_ARTIFACTS)/secret-access-key.json

kops-bucket:
	aws s3api create-bucket \
		--create-bucket-configuration LocationConstraint=$(AWS_REGION) \
		--bucket $(CLUSTER_NAME)-state-store-$(shell uuidgen | cut -c -8) \
		--region $(AWS_REGION) \
		| tee $(CLUSTER_ARTIFACTS)/create-bucket.json

KOPS_BUCKET = $(shell jq --raw-output .Location $(CLUSTER_ARTIFACTS)/create-bucket.json \
			  | cut -c 8- \
			  | sed 's/\..*//')
kops-configure-bucket:
	aws s3api put-bucket-versioning \
		--bucket $(KOPS_BUCKET) \
		--versioning-configuration Status=Enabled

kops-oidc-bucket:
	aws s3api create-bucket \
		--create-bucket-configuration LocationConstraint=$(AWS_REGION) \
		--region $(AWS_REGION) \
		--bucket $(CLUSTER_NAME)-oidc-store-$(shell uuidgen | cut -c -8) \
		--object-ownership BucketOwnerPreferred \
		| tee $(CLUSTER_ARTIFACTS)/create-oidc-bucket.json

KOPS_OIDC_BUCKET = $(shell jq --raw-output .Location $(CLUSTER_ARTIFACTS)/create-oidc-bucket.json \
				   | cut -c 8- \
				   | sed 's/\..*//')
kops-configure-oidc-bucket:
	aws s3api put-public-access-block \
		--bucket $(KOPS_OIDC_BUCKET) \
		--public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
	aws s3api put-bucket-acl \
		--bucket $(KOPS_OIDC_BUCKET) \
		--acl public-read

KOPS_NAME=$(CLUSTER_NAME).k8s.local
KOPS=NAME=$(KOPS_NAME) \
		KOPS_STATE_STORE=s3://$(KOPS_BUCKET) \
		AWS_ACCESS_KEY_ID=$(shell jq --raw-output .AccessKey.AccessKeyId $(CLUSTER_ARTIFACTS)/secret-access-key.json) \
		AWS_SECRET_ACCESS_KEY=$(shell jq --raw-output .AccessKey.SecretAccessKey $(CLUSTER_ARTIFACTS)/secret-access-key.json) \
		kops

ZONES=$(AWS_REGION)c
kops-template:
	$(KOPS) create cluster $(KOPS_NAME) \
		--cloud aws \
		--zones "$(ZONES)" \
		--node-size m5.xlarge \
		--master-zones "$(ZONES)" \
		--master-size t3.medium \
		--discovery-store s3://$(KOPS_OIDC_BUCKET)/$(KOPS_NAME)/discovery \
		--dry-run \
		-o yaml > $(CLUSTER_ARTIFACTS)/cluster.yaml

kops-delete:
	$(KOPS) delete cluster --name $(KOPS_NAME) --yes

kops-init:
	$(KOPS) create -f $(CLUSTER_ARTIFACTS)/cluster.yaml

kops-replace:
	$(KOPS) replace -f $(CLUSTER_ARTIFACTS)/cluster.yaml

kops-update:
	$(KOPS) update cluster --name $(KOPS_NAME) --yes --admin

kops-edit:
	$(KOPS) edit instancegroup nodes-us-west-2c

kops-rolling-update:
	$(KOPS) rolling-update cluster --yes --force --cloudonly

kops-validate:
	$(KOPS) validate cluster --wait 10m

$(CLUSTER_NAME)-resources-create: 
	$(HELM_TEMPLATE) | kubectl create --save-config -f -

$(CLUSTER_NAME)-resources-delete:
	$(HELM_TEMPLATE) | kubectl delete -f -

$(CLUSTER_NAME)-resources-apply:
	$(HELM_TEMPLATE) | kubectl apply -f -

.PHONY: $(CLUSTER_NAME)-*

CRDS = customresourcedefinition/rayclusters.ray.io \
customresourcedefinition/rayjobs.ray.io \
customresourcedefinition/rayservices.ray.io
$(CLUSTER_NAME)-crds:
	$(foreach crd,$(CRDS),\
		kubectl describe $(crd) 2> /dev/null ;\
		if [[ $$? == '0' ]]; then \
			echo deleting ;\
			kubectl delete $(crd) ;\
		fi; \
	)
	cat $(HELM_VALUES) \
		| $(HELM_ENV) envsubst \
		| helm template softgrep deploy/chart --values - --include-crds \
		| yq 'select(.kind == "CustomResourceDefinition")' \
		| kubectl create -f -

.PHONY: $(CLUSTER_NAME)-*

# TEST
SERVER_URL = $(shell kubectl get service/softgrep --output json \
	| jq .status.loadBalancer.ingress[0].hostname --raw-output)
test-predict:
	time grpcurl -proto pb/softgrep.proto -plaintext "$(SERVER_URL):50051" softgrep.Model/Predict \
		<< ./testdata/requests/predict/hello.json

