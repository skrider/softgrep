PYTHON = PYTHONPATH="$(CWD):${PYTHONPATH}" \
	LD_LIBRARY_PATH="${SOFTGREP_NIX_CC_LIB}" \
	venv/bin/python

OUT = $(shell pwd)/build

pb: pb/softgrep.proto
	$(PYTHON) -m grpc_tools.protoc \
		-Ipb --python_out=pb --pyi_out=pb --grpc_python_out=pb pb/softgrep.proto
	protoc --go_out=. --go_opt=paths=source_relative \
		--go-grpc_out=. --go-grpc_opt=paths=source_relative \
		pb/softgrep.proto
.PHONY: pb

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

build:
	go build -o $(OUT)/softgrep cmd/softgrep/main.go 
.PHONY: build

BENCHLOG = $(OUT)/benchmark.log
BENCHCMD = $(OUT)/softgrep ./testdata/grpc
benchmark: build
	echo --- >> $(BENCHLOG)
	echo $(MESSAGE) >> $(BENCHLOG)
	git rev-parse HEAD >> $(BENCHLOG)
	echo $(BENCHCMD): >> $(BENCHLOG)
	time --append --output=$(BENCHLOG) $(BENCHCMD)
	cat $(BENCHLOG) | tail -n 5

# SERVER

LOCAL_TAG = softgrep/server
server:
	DOCKER_BUILDKIT=0 docker build . \
		-t $(LOCAL_TAG)

SERVER_ARTIFACTS = ./deploy/artifacts/server
ECR_JSON = $(SERVER_ARTIFACTS)/ecr-create-repository.json
create-ecr-repo:
	mkdir -p $(SERVER_ARTIFACTS)
	aws ecr create-repository \
		--repository-name softgrep/server \
		--no-cli-pager | tee $(ECR_JSON)

docker-login:
	aws ecr get-login-password --region $(REGION) \
		| docker login \
			--username AWS \
			--password-stdin $(shell cat $(ECR_JSON) | jq .repository.repositoryUri)

publish-server:
	docker tag $(LOCAL_TAG):latest $(shell cat $(ECR_JSON) | jq --raw-output .repository.repositoryUri):latest
	docker push $(shell cat $(ECR_JSON) | jq --raw-output .repository.repositoryUri):latest

# DEPLOYMENT

REGION = us-west-2

bootstrap-cluster:
	helm repo add kuberay https://ray-project.github.io/kuberay-helm/
	helm template kuberay-operator kuberay/kuberay-operator --version 0.5.0 | kubectl apply -f -
	echo "Press enter when operator is deployed"
	read
	helm template raycluster kuberay/ray-cluster --version 0.5.0 | kubectl apply -f -
	kubectl get pods

exec-head:
	kubectl exec -it \
		$(shell kubectl get pods --selector=ray.io/node-type=head -o custom-columns=POD:metadata.name --no-headers) \
		-- \
		python -c "import ray; ray.init(); print(ray.cluster_resources())"

expose:
	kubectl port-forward --address 0.0.0.0 service/raycluster-kuberay-head-svc 8265:8265

cluster:
	eksctl create cluster -f deploy/cluster.yaml

