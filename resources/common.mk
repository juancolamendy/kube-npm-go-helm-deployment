# Variables

## Set defaults
DEFAULT_BASE_DIR=deployment

## Apply defaults
BASE_DIR ?= $(DEFAULT_BASE_DIR)

## Application
BIN_NAME=${APP_NAME}.bin

## Environment
GIT_BRANCH=$(shell git rev-parse --abbrev-ref HEAD)
ENV_DIR=${BASE_DIR}/resources/deploy/${APP_NAME}/helm/env/${GIT_BRANCH}

# Kubernetes
KUBECONFIG=${ENV_DIR}/admin.conf

# Helm
HELM_VALUES=${ENV_DIR}/values.yaml
HELM_BASE=${BASE_DIR}/resources/deploy/${APP_NAME}/helm/${APP_NAME}
DEPLOY_HELM_DIR=helm/charts

## Docker
DOCKERFILE_TEMPLATE=${BASE_DIR}/resources/deploy/${APP_NAME}/Dockerfile.tpl

## Tag variables
TAG_VERSION=$(shell git describe)
TAG_VERSION_FILE=helm/tagversionfile.txt

## Registry variables
DOCKER_SECRET_KEY_NAME=${APP_NAME}-secret-key

# Targets
## General
.PHONY: print-vars
print-vars:
	@echo "Print vars:"; \
	echo "BASE_DIR: ${BASE_DIR}"; \
	echo "CODE_ENTRY: ${CODE_ENTRY}"; \
	echo "BIN_DIR: ${BIN_DIR}"; \
	echo "APP_NAME: ${APP_NAME}"; \
	echo "NAMESPACE: ${NAMESPACE}"; \
	echo "GIT_BRANCH: ${GIT_BRANCH}"; \
	echo "ENV_DIR: ${ENV_DIR}"; \
	echo "KUBECONFIG: ${KUBECONFIG}"; \
	echo "DOCKERFILE_TEMPLATE: ${DOCKERFILE_TEMPLATE}"; \
	echo "TAG_VERSION: ${TAG_VERSION}" ;\
	echo "DOCKER_REGISTRY: ${DOCKER_REGISTRY}" ;\
	echo "DOCKER_USERNAME: ${DOCKER_USERNAME}" ;\
	echo "DOCKER_EMAIL: ${DOCKER_EMAIL}" ;\
	echo "DOCKER_PASSWORD: ${DOCKER_PASSWORD}" ;\
	echo "DOCKER_REPOSITORY: ${DOCKER_REPOSITORY}" ;\
	echo "DEPLOY_HELM_DIR: ${DEPLOY_HELM_DIR}" ;\
	echo "HELM_BASE: ${HELM_BASE}"; \
	echo "TAG_VERSION_FILE: ${TAG_VERSION_FILE}"; \
	echo "HELM_VALUES: ${HELM_VALUES}"

## NPM
.PHONY: npm-release
npm-release: helm-deploy

.PHONY: npm-docker-build
npm-docker-build: docker-build

.PHONE: npm-build
npm-build:
	@echo "--- Building ..."; \
	npm run build

.PHONY: npm-run
npm-run:
	@echo "--- Running locally ..."; \
	source ./resources/deploy/helm/env/local/env.sh && npm run runDev

.PHONY: npm-clean
npm-clean:
	@echo "--- Cleaning ..."; \
	npm run clean

## Go
.PHONY: go-release
go-release: go-build-linux helm-deploy

.PHONY: go-docker-build
go-docker-build: go-build-linux docker-build

.PHONY: compile
go-compile:
	@echo "--- Compiling ..."; \
	rm -f ${BIN_DIR}${BIN_NAME}; \
	go build -v -i -o ${BIN_DIR}${BIN_NAME} ${CODE_ENTRY}

.PHONY: build
go-build:
	@echo "--- Building ..."; \
	rm -f ${BIN_DIR}${BIN_NAME}; \
	go build -v -i -o ${BIN_DIR}${BIN_NAME} ${CODE_ENTRY}

.PHONY: build-linux
go-build-linux:
	@echo "--- Building for linux arch ..."; \
	rm -f ${BIN_DIR}${BIN_NAME}; \
	CGO_ENABLED=0 GOOS=linux go build -v -i -o ${BIN_DIR}${BIN_NAME} ${CODE_ENTRY}

.PHONY: run
go-run:
	@ echo "--- Running locally ..."; \
	source ./resources/deploy/helm/env/local/env.sh && go run ${CODE_ENTRY}

.PHONY: clean
go-clean:
	@echo "--- Cleaning ..."; \
	rm -f ${BIN_DIR}$(BIN_NAME)

## Tag
.PHONY: create-tag
create-tag:
	@echo "--- Creating tag" ;\
	git tag -a v0.0.1 -m"init version" ;\
	git push --tags

## Docker
.PHONY: docker-update-img
docker-update-img:
	@echo "--- Updating image ..." ;\
	if [ -f ${TAG_VERSION_FILE} ]; then \
		echo "--- Previous tag file found" ;\
		echo "--- Deleting image ${DOCKER_USERNAME}/${BIN_NAME}:$(shell cat ${TAG_VERSION_FILE})" ;\
		docker rmi ${DOCKER_USERNAME}/${DOCKER_REPOSITORY}:$(shell cat ${TAG_VERSION_FILE}) ;\
		echo "--- Trying to delete the image remotely" ;\
		TOKEN=$$(curl -s -H "Content-Type: application/json" -X POST -d '{"username": "'${DOCKER_USERNAME}'", "password": "'${DOCKER_PASSWORD}'"}' https://hub.docker.com/v2/users/login/ | jq -r .token) ;\
		curl "https://hub.docker.com/v2/repositories/${DOCKER_USERNAME}/${DOCKER_REPOSITORY}/tags/$(shell cat ${TAG_VERSION_FILE})/" \
		-X DELETE \
		-H "Authorization: JWT $${TOKEN}" ;\
	fi ;

.PHONY: docker-build
docker-build: docker-update-img
	@echo "--- Docker building ..." ;\
	cat ${DOCKERFILE_TEMPLATE} | sed -e "s/{{BIN_NAME}}/${BIN_NAME}/g" | sed -e "s/{{PORT}}/${PORT}/g" > Dockerfile ;\
	docker build -t ${DOCKER_USERNAME}/${DOCKER_REPOSITORY}:${TAG_VERSION} . ;\
	rm -f Dockerfile

.PHONY: docker-run
docker-run:
	@ echo "--- Running image ..." ;\
	docker run --rm -p ${PORT}:${PORT} ${DOCKER_USERNAME}/${DOCKER_REPOSITORY}:${TAG_VERSION}

.PHONY: docker-rmi
docker-rmi:
	@ echo "--- Removing image ..." ;\
	docker rmi ${DOCKER_USERNAME}/${DOCKER_REPOSITORY}:${TAG_VERSION}

.PHONY: docker-push
docker-push: docker-build
	@echo "--- Docker push to repository" ;\
	docker login -u ${DOCKER_USERNAME} -p ${DOCKER_PASSWORD} ;\
	docker push ${DOCKER_USERNAME}/${DOCKER_REPOSITORY}:${TAG_VERSION} ;\
	docker logout ;\
	echo "--- Creating a new tag file" ;\
	echo "${TAG_VERSION}" > ${TAG_VERSION_FILE}

.PHONY: docker-rm-dangling
docker-rm-dangling:
	@ echo "--- Removing dangling images ..."; \
	docker rmi $$(docker images --quiet --filter "dangling=true")

## Kubernetes
.PHONY: kube-init
kube-init: kube-create-ns kube-create-secret

.PHONY: kube-create-ns
kube-create-ns:
	@ echo "--- Creating namespace ..."; \
	kubectl create namespace ${NAMESPACE} --kubeconfig ${KUBECONFIG}

.PHONY: kube-create-secret
kube-create-secret:
	@ echo "--- Creating secret ..."; \
	kubectl create secret docker-registry ${DOCKER_SECRET_KEY_NAME} --docker-server=${DOCKER_REGISTRY} --docker-username=${DOCKER_USERNAME} --docker-password=${DOCKER_PASSWORD} --docker-email=${DOCKER_EMAIL} --kubeconfig ${KUBECONFIG} --namespace=${NAMESPACE}

.PHONY: kube-delete-secret
kube-delete-secret:
	@ echo "--- Deleting secret ..."; \
	kubectl delete secret ${DOCKER_SECRET_KEY_NAME} --kubeconfig ${KUBECONFIG} --namespace=${NAMESPACE}

.PHONY: helm-package
helm-package: docker-push
	@echo "--- Helm package" ;\
	helm package --kubeconfig ${KUBECONFIG} --app-version=${TAG_VERSION} --version=${TAG_VERSION} --destination=$(DEPLOY_HELM_DIR) ${HELM_BASE}

.PHONE: helm-inspect-values
helm-inspect-values:
	@echo "--- Inspecting helm values" ;\
	helm inspect values $(DEPLOY_HELM_DIR)/${APP_NAME}-${TAG_VERSION}.tgz

.PHONE: helm-inspect-output
helm-inspect-output:
	@echo "--- Helm inspect output" ;\
	helm template $(DEPLOY_HELM_DIR)/${APP_NAME}-${TAG_VERSION}.tgz

.PHONY: helm-deploy
helm-deploy: helm-package
	@echo "--- Helm deploy" ;\
	helm upgrade -i ${APP_NAME} $(DEPLOY_HELM_DIR)/${APP_NAME}-${TAG_VERSION}.tgz --values=${HELM_VALUES} --namespace=$(NAMESPACE) --kubeconfig ${KUBECONFIG} --wait
	rm -f $(DEPLOY_HELM_DIR)/${APP_NAME}-${TAG_VERSION}.tgz

.PHONY: helm-list
helm-list:
	@echo "--- Listing helm" ;\
	helm list --kubeconfig ${KUBECONFIG} --all-namespaces

.PHONY: helm-delete
helm-delete:
	@echo "--- Helm delete" ;\
	helm delete --purge ${APP_NAME} --kubeconfig ${KUBECONFIG}

.PHONY: kube-ls-pod
kube-ls-pod:
	@echo "--- Listing pods"; \
	kubectl --kubeconfig ${KUBECONFIG} --namespace=${NAMESPACE} get pods

.PHONY: helm-rollback
helm-rollback:
	@echo "--- Helm rollback" ;\
	helm rollback ${APP_NAME} 0 --namespace=${NAMESPACE} --kubeconfig ${KUBECONFIG}

.PHONY: kube-connect-pod
kube-connect-pod:
	@echo "Please, provide a name for pod:" ;\
	read POD_NAME ;\
	kubectl --kubeconfig ${KUBECONFIG}  --namespace=${NAMESPACE} exec -it $$POD_NAME sh	

.PHONY: kube-logs-pod
kube-logs-pod:
	echo "Please, provide a name for pod:" ;\
	read POD_NAME ;\
	kubectl --kubeconfig ./${KUBECONFIG} --namespace=${NAMESPACE} logs -f $$POD_NAME

.PHONY: kube-clean
kube-clean: helm-delete kube-rm-current-image clean
