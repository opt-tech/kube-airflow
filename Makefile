AIRFLOW_VERSION ?= 1.8.2rc1
# curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt
KUBECTL_VERSION ?= v1.7.3
KUBE_AIRFLOW_VERSION ?= 0.21
GCP_PROJECT_ID ?=$(PROJECT_ID)
GCP_JSON_KEY ?=${GCP_JSON_PATH}

REPOSITORY ?= ming-cho/kube-airflow
TAG ?= $(AIRFLOW_VERSION)-$(KUBECTL_VERSION)-$(KUBE_AIRFLOW_VERSION)
IMAGE ?= $(REPOSITORY)
ALIAS ?= gcr.io/$(GCP_PROJECT_ID)/$(IMAGE)

BUILD_ROOT ?= build/$(TAG)
DOCKERFILE ?= $(BUILD_ROOT)/Dockerfile
ROOTFS ?= $(BUILD_ROOT)/rootfs
AIRFLOW_CONF ?= $(BUILD_ROOT)/config/airflow.cfg
ENTRYPOINT_SH ?= $(BUILD_ROOT)/script/entrypoint.sh
ENTRYPOINT_DIR=$(shell dirname $(ENTRYPOINT_SH))
DOCKER_CACHE ?= docker-cache
SAVED_IMAGE ?= $(DOCKER_CACHE)/image-$(AIRFLOW_VERSION)-$(KUBECTL_VERSION).tar

NAMESPACE ?= airflow-dev

.PHONY: build clean

clean:
	rm -Rf build

build: $(DOCKERFILE) $(ROOTFS) $(AIRFLOW_CONF) entries dags
	cd $(BUILD_ROOT) && docker build -t $(IMAGE):$(TAG) . && docker tag $(IMAGE):$(TAG) $(ALIAS):$(TAG)
	@echo "INOF: image:$(IMAGE):$(TAG) ALIAS:$(ALIAS):$(TAG) is built"

publish:
	@echo "INFO: to publish $(ALIAS):$(TAG)"
	gcloud docker -- push $(ALIAS)
	gcloud container images list-tags $(ALIAS)

$(DOCKERFILE): $(BUILD_ROOT)
	sed -e 's/%%KUBECTL_VERSION%%/'"$(KUBECTL_VERSION)"'/g;' -e 's/%%AIRFLOW_VERSION%%/'"$(AIRFLOW_VERSION)"'/g;' Dockerfile.template > $(DOCKERFILE)

$(ROOTFS): $(BUILD_ROOT)
	mkdir -p rootfs
	cp -R rootfs $(ROOTFS)

$(AIRFLOW_CONF): $(BUILD_ROOT)
	mkdir -p $(shell dirname $(AIRFLOW_CONF))
	cp config/airflow.cfg $(AIRFLOW_CONF)

entries: $(BUILD_ROOT)
	mkdir -p $(ENTRYPOINT_DIR)
	cp script/entrypoint.sh $(ENTRYPOINT_SH)
	cp script/init_meta_db.py $(ENTRYPOINT_DIR)/
	cp -R instance $(BUILD_ROOT)/

dags: $(BUILD_ROOT)
	cp -R ../airflow_home/dags $(BUILD_ROOT)/
	cp -R ../airflow_home/plugins $(BUILD_ROOT)/
	cp  $(GCP_JSON_KEY) $(BUILD_ROOT)/gcp-airflow.json

$(BUILD_ROOT):
	mkdir -p $(BUILD_ROOT)

travis-env:
	travis env set DOCKER_EMAIL $(DOCKER_EMAIL)
	travis env set DOCKER_USERNAME $(DOCKER_USERNAME)
	travis env set DOCKER_PASSWORD $(DOCKER_PASSWORD)

test:
	@echo There are no tests available for now. Skipping

save-docker-cache: $(DOCKER_CACHE)
	docker save $(IMAGE) $(shell docker history -q $(IMAGE) | tail -n +2 | grep -v \<missing\> | tr '\n' ' ') > $(SAVED_IMAGE)
	ls -lah $(DOCKER_CACHE)

load-docker-cache: $(DOCKER_CACHE)
	if [ -e $(SAVED_IMAGE) ]; then docker load < $(SAVED_IMAGE); fi

$(DOCKER_CACHE):
	mkdir -p $(DOCKER_CACHE)

create:
	if ! kubectl get namespace $(NAMESPACE) >/dev/null 2>&1; then \
	  kubectl create namespace $(NAMESPACE); \
	fi
	kubectl create -f airflow.all.yaml --save-config --namespace $(NAMESPACE)

apply:
	kubectl apply -f airflow.all.yaml --namespace $(NAMESPACE)

delete:
	kubectl delete -f airflow.all.yaml --namespace $(NAMESPACE)

list-pods:
	kubectl get po -a --namespace $(NAMESPACE)

list-services:
	kubectl get svc -a --namespace $(NAMESPACE)

# pod_name="web-2874099158-lxgm2" make login-pod
login-pod:
	kubectl --namespace $(NAMESPACE) exec -it $(pod_name) -- /bin/bash

browse-web:
	minikube service web -n $(NAMESPACE)

browse-flower:
	minikube service flower -n $(NAMESPACE)
