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

