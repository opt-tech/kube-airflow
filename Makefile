AIRFLOW_VERSION ?= 1.8.2
# curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt
KUBECTL_VERSION ?= v1.7.3
KUBE_AIRFLOW_VERSION ?= $(VERSION)
GCP_PROJECT_ID ?=$(PROJECT_ID)
GCP_JSON_KEY ?=${GCP_JSON_PATH}

REPOSITORY ?= airflow-dev/kube-airflow
TAG ?= $(AIRFLOW_VERSION)-$(KUBECTL_VERSION)-$(KUBE_AIRFLOW_VERSION)
IMAGE ?= $(REPOSITORY)
ALIAS ?= gcr.io/$(GCP_PROJECT_ID)/$(IMAGE)
REMOTE_IMAGE_PATH=${ALIAS}:${TAG}

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

publish: build
	@echo "INFO: to publish $(ALIAS):$(TAG)"
	gcloud docker -- push $(ALIAS):$(TAG)
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

apply: publish
	cat airflow.all.yaml | sed -e 's|%%REMOTE_IMAGE_PATH%%|$(REMOTE_IMAGE_PATH)|g' | kubectl --namespace $(NAMESPACE) apply --record -f -

# edit or replace
# flower should be updated when the version of airflow is changed
rolling-update:
	kubectl --namespace $(NAMESPACE) set image deployment/web web=$(REMOTE_IMAGE_PATH) --record
	kubectl --namespace $(NAMESPACE) set image deployment/worker worker=$(REMOTE_IMAGE_PATH) --record
	kubectl --namespace $(NAMESPACE) set image deployment/scheduler scheduler=$(REMOTE_IMAGE_PATH) --record

#--to-revision=<revision>
rollback:
	kubectl --namespace $(NAMESPACE) rollout undo deployment web
	kubectl --namespace $(NAMESPACE) rollout undo deployment worker
	kubectl --namespace $(NAMESPACE) rollout undo deployment scheduler

deploy:
	cat airflow.all.yaml | sed -e 's|%%REMOTE_IMAGE_PATH%%|$(REMOTE_IMAGE_PATH)|g' | kubectl --namespace $(NAMESPACE) apply --record -f -

#delete:
#	kubectl delete -f airflow.all.yaml --namespace $(NAMESPACE)

list-pods:
	kubectl get po -a --namespace $(NAMESPACE)

list-services:
	kubectl get svc -a --namespace $(NAMESPACE)

# pod_name=web-2874099158-lxgm2 make login-pod
login-pod:
	kubectl --namespace $(NAMESPACE) exec -it $(pod_name) -- /bin/bash

# pod_name=web-2874099158-lxgm2 make describe-pod
describe-pod:
	kubectl describe pod/$(pod_name) --namespace $(NAMESPACE)

browse-web:
	kubectl --namespace airflow-dev port-forward $(shell make list-pods | grep web- | cut -d' ' -f1) 8080:8080

browse-flower:
	kubectl --namespace airflow-dev port-forward $(shell make list-pods | grep flower- | cut -d' ' -f1) 5555:5555
