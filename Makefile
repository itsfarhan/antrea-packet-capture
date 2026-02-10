.PHONY: help setup test e2e build load deploy clean clean-cluster

IMAGE_NAME := packet-capture:latest
CLUSTER_NAME := antrea-test

help:
	@echo "Antrea Packet Capture Controller - Makefile Commands"
	@echo ""
	@echo "  make setup         - Complete setup: create cluster, install Antrea, build and deploy"
	@echo "  make test          - Run end-to-end test: deploy test pod, capture packets, verify"
	@echo "  make e2e           - Full end-to-end: setup + test (one command!)"
	@echo "  make build         - Build Docker image"
	@echo "  make load          - Load Docker image into Kind cluster"
	@echo "  make deploy        - Deploy controller DaemonSet"
	@echo "  make clean         - Clean up test pod and controller"
	@echo "  make clean-cluster - Delete Kind cluster"

setup:
	@./setup.sh

test:
	@./test.sh

e2e: setup test

build:
	docker build -t $(IMAGE_NAME) .

load:
	kind load docker-image $(IMAGE_NAME) --name $(CLUSTER_NAME)

deploy:
	kubectl apply -f manifests/daemonset.yaml

clean:
	kubectl delete -f manifests/test-pod.yaml --ignore-not-found
	kubectl delete -f manifests/daemonset.yaml --ignore-not-found

clean-cluster:
	kind delete cluster --name $(CLUSTER_NAME)
