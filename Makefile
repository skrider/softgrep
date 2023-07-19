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
DEPLOY_ARTIFACTS = ./deploy/artifacts
DEPLOY_ENV = $(if $(SOFTGREP_ENV),$(SOFTGREP_ENV),development)
AWS_REGION = us-west-2
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
EKS_CONFIG_FILE = deploy/cluster.$(DEPLOY_ENV).yaml
HELM_VALUES = ./deploy/chart/values.$(DEPLOY_ENV).yaml
HELM_ENV = IMAGE_REPOSITORY=$(SERVER_ECR_REPO)
HELM_TEMPLATE = cat $(HELM_VALUES) \
	| $(HELM_ENV) envsubst \
	| helm template softgrep deploy/chart --skip-crds --values -

$(CLUSTER_NAME)-create:
	cat $(EKS_CONFIG_FILE) \
		| CLUSTER_NAME=$(CLUSTER_NAME) AWS_REGION=$(AWS_REGION) envsubst \
		| eksctl create cluster -f -

$(CLUSTER_NAME)-delete:
	eksctl delete cluster --name $(CLUSTER_NAME)

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
		kubectl describe $$crd 2> /dev/null ;\
		if [[ $$? == '0' ]]; then \
			echo deleting ;\
			kubectl delete $$crd ;\
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

