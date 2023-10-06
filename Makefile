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
DEPLOY_ENV = $(if $(SOFTGREP_ENV),$(SOFTGREP_ENV),development)
AWS_REGION = us-west-2

HELM_VALUES = ./deploy/chart/values.$(DEPLOY_ENV).yaml
HELM_ENV = IMAGE_REPOSITORY=$(TF_OUT_)
HELM_TEMPLATE = cat $(HELM_VALUES) \
        | $(shell $(TERRAFORM) output | sed -e 's/^/TF_OUT_/' -e 's/\s=\s/=/' -e '/<sensitive>$$/d') envsubst \
        | helm template softgrep deploy/chart --skip-crds --values -
apply:
	$(HELM_TEMPLATE) | kubectl apply -f -

# SERVER
LOCAL_TAG = softgrep/server
SERVER_ARTIFACTS = $(DEPLOY_ARTIFACTS)/server
ECR_JSON = $(SERVER_ARTIFACTS)/ecr-create-repository.json
TERRAFORM = terraform -chdir=deploy
SERVER_ECR_REPO=$(shell $(TERRAFORM) output -raw server_ecr_url)
ecr-login:
	aws ecr get-login-password --region $(AWS_REGION) \
		| docker login \
			--username AWS \
			--password-stdin $(SERVER_ECR_REPO)

ecr-publish:
	docker tag $(LOCAL_TAG):latest $(SERVER_ECR_REPO):latest
	docker push $(SERVER_ECR_REPO):latest

ter-apply:
	$(TERRAFORM) apply

ter-apply-prebuild:
	$(TERRAFORM) apply -target=aws_ecr_repository.server

ter-destroy:
	$(TERRAFORM) destroy

ter-console:
	$(TERRAFORM) console

ter-apply-kubeconfig:
	aws eks --region $(AWS_REGION) update-kubeconfig \
		--name $(shell $(TERRAFORM) output -raw cluster_name)

ssh-add:
	$(TERRAFORM) output -raw bastion_private_key | ssh-add -
	$(TERRAFORM) output -raw cluster_private_key | ssh-add -

bastion-ip:
	@$(TERRAFORM) output -raw bastion_public_ip

# TEST
SERVER_URL = $(shell kubectl get service/softgrep --output json \
	| jq .status.loadBalancer.ingress[0].hostname --raw-output)
test-predict:
	time grpcurl -proto pb/softgrep.proto -plaintext "$(SERVER_URL):50051" softgrep.Model/Predict \
		< ./testdata/requests/predict/hello.json

