.PHONY: build load deploy test clean

IMAGE_NAME := packet-capture:latest

build:
	docker build -t $(IMAGE_NAME) .

load:
	kind load docker-image $(IMAGE_NAME)

deploy:
	kubectl apply -f manifests/daemonset.yaml

test:
	kubectl apply -f manifests/test-pod.yaml

clean:
	kubectl delete -f manifests/test-pod.yaml --ignore-not-found
	kubectl delete -f manifests/daemonset.yaml --ignore-not-found
