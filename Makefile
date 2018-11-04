CHART_REPOSITORY := $(or $(CHART_REPOSITORY),http://jenkins-x-chartmuseum:8080)
CURRENT := $(shell pwd)
NAME := $(or $(APP_NAME), $(shell basename $(CURRENT)))
OS := $(shell uname)
RELEASE_VERSION := $(or $(shell cat VERSION), $(shell sed -n 's/^version: //p' Chart.yaml))

RELEASE_BRANCH := $(or $(CHANGE_TARGET), $(shell git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'))
RELEASE_GREP_EXPR := '^[Rr]elease'

GITHUB_CHARTS_BRANCH := $(or $(GITHUB_CHARTS_BRANCH),gh-pages)
GITHUB_CHARTS_REPO := $(or $(GITHUB_CHARTS_REPO),$(shell git config --get remote.origin.url))
GITHUB_CHARTS_DIR := $(or $(GITHUB_CHARTS_DIR),$(shell basename $(GITHUB_CHARTS_REPO) .git))

GS_BUCKET_CHARTS_REPO := $(or $(GS_BUCKET_CHARTS_REPO),$(ORG)-charts)

.PHONY: ;

$(NAME)-$(RELEASE_VERSION).tgz: 
	${MAKE} package

git-rev-list: .PHONY
	$(eval REV = $(shell git rev-list --tags --max-count=1 --grep $(RELEASE_GREP_EXPR)))
	$(eval PREVIOUS_REV = $(shell git rev-list --tags --max-count=1 --skip=1 --grep $(RELEASE_GREP_EXPR)))
	$(eval REV_TAG = $(shell git describe ${PREVIOUS_REV}))
	$(eval PREVIOUS_REV_TAG = $(shell git describe ${REV}))
	@echo Found commits between $(PREVIOUS_REV_TAG) and $(REV_TAG) tags:
	git rev-list $(PREVIOUS_REV)..$(REV) --first-parent --pretty

init:
	helm init --client-only
	helm repo add chart-repo $(CHART_REPOSITORY)

lint: clean init
	rm -rf requirements.lock
	helm dependency build
	helm lint

version: 
	$(shell jx-release-version > VERSION)
	@echo Using next release version $(shell cat VERSION)

next-version: 
	jx step next-version
	
tag:	
	jx step tag --charts-dir . --version $(RELEASE_VERSION)

credentials: 
	git config --global credential.helper store
	jx step git credentials

checkout: credentials
	@echo "ensure we're not on a detached head"
	git checkout $(RELEASE_BRANCH) 

package: build 
	helm package .

install: clean build
	helm install . --name ${NAME}

upgrade: clean build
	helm upgrade ${NAME} .

delete:
	helm delete --purge ${NAME}

clean:
	rm -rf charts
	rm -rf ${NAME}*.tgz

deploy: $(NAME)-$(RELEASE_VERSION).tgz
	curl --fail -u $(CHARTMUSEUM_CREDS_USR):$(CHARTMUSEUM_CREDS_PSW) --data-binary "@$(NAME)-$(RELEASE_VERSION).tgz" $(CHART_REPOSITORY)/api/charts
	rm -rf ${NAME}*.tgz%
	
# run this command inside 'gsutil' container in Jenkinsfile pipeline
chartmuseum: $(NAME)-$(RELEASE_VERSION).tgz
	curl --fail -L $(CHART_REPOSITORY)/index.yaml | gsutil cp - "gs://$(GS_BUCKET_CHARTS_REPO)/index.yaml"
	
github: $(NAME)-$(RELEASE_VERSION).tgz
	git clone -b "$(GITHUB_CHARTS_BRANCH)" "$(GITHUB_CHARTS_REPO)" $(GITHUB_CHARTS_DIR)
	cp "$(NAME)-$(RELEASE_VERSION).tgz" $(GITHUB_CHARTS_DIR)
	cd $(GITHUB_CHARTS_DIR) && \
	   helm repo index . && \
	   git add . && \
	   git status && \
	   git commit -m "fix: (version) add $(NAME)-$(RELEASE_VERSION) chart" && \
	   git push origin "$(GITHUB_CHARTS_BRANCH)"
	   rm -rf $(GITHUB_CHARTS_DIR)
	   
release:
	jx step helm release
	
build:
	jx step helm build	
	
promote:
	jx promote -b --all-auto --timeout 1h --version $(RELEASE_VERSION)	

changelog: git-rev-list
	@echo Creating Github changelog for release: $(RELEASE_VERSION)
	jx step changelog --version v$(RELEASE_VERSION) --generate-yaml=true --rev=$(REV) --previous-rev=$(PREVIOUS_REV)
